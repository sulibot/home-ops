# VolSync + Kopia Backup and Restore System

## Overview

This document explains how the VolSync + Kopia backup system works in this Kubernetes cluster. This system provides automated backup and restore capabilities for application persistent volumes using Kopia as the backup engine and VolSync as the orchestration layer.

## Architecture

### Components

1. **Kopia Repository** - Centralized backup storage
   - Location: `kopia` PVC in `volsync-system` namespace
   - Storage: CephFS (`csi-cephfs-config-sc`)
   - Shared across all applications for deduplication
   - Encrypted with password from `kopia-secret`

2. **VolSync Operator** - Backup/restore orchestration
   - Deployed in `volsync-system` namespace
   - Manages ReplicationSource (backup) and ReplicationDestination (restore) resources
   - Creates jobs to execute backup/restore operations

3. **Per-Application Resources**
   - ReplicationSource: Handles scheduled backups
   - ReplicationDestination: Handles automatic restores
   - ExternalSecret: Provides Kopia repository credentials
   - Application PVC: The data being backed up

4. **MutatingAdmissionPolicy** (Requires Kubernetes 1.34+)
   - Automatically injects Kopia repository volume into maintenance jobs
   - Handles repository compaction, garbage collection, etc.
   - File saved at: `/docs/volsync-kopia-mutatingadmissionpolicy.yaml`
   - Currently disabled (cluster on k8s 1.31)

## How It Works

### Initial Setup (One-Time)

1. **Kopia Repository Initialization**
   ```bash
   # Repository created at /repository in the kopia PVC
   kopia repository create filesystem --path=/repository
   ```

2. **VolSync Component Applied to Apps**
   - Each app's Flux Kustomization includes the volsync component:
     ```yaml
     components:
       - ../../../../components/volsync
     ```

3. **Component Creates Per-App Resources**
   - `${APP}-volsync-secret` ExternalSecret (Kopia credentials)
   - `${APP}-config` PVC (managed by ReplicationDestination)
   - `${APP}-src` ReplicationSource (backup scheduler)
   - `${APP}-dst` ReplicationDestination (restore handler)

### Backup Flow (Hourly)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Scheduled Trigger (Every Hour)                          │
│    ReplicationSource spec.trigger.schedule: "0 * * * *"    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Create VolumeSnapshot                                    │
│    CSI driver creates snapshot: ${APP}-config-snapshot      │
│    Storage: CephFS snapshot class                           │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Launch Kopia Backup Job                                  │
│    Pod: volsync-src-${APP}-${timestamp}                     │
│    Mounts:                                                   │
│      - Source: ${APP}-config-snapshot (read-only)           │
│      - Repository: kopia PVC (via repositoryPVC)            │
│      - Cache: kopia-cache-${APP} PVC                        │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Kopia Backup Process                                     │
│    - Connect to repository using ${APP}-volsync-secret      │
│    - Read data from snapshot                                │
│    - Chunk, deduplicate, compress (zstd-fastest)            │
│    - Write to repository with 2 parallel streams            │
│    - Apply retention: 24 hourly, 7 daily                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Update Status                                            │
│    ReplicationSource.status:                                │
│      lastSyncTime: 2025-11-21T00:01:09Z                     │
│      lastSyncDuration: 1m9.111183003s                       │
│      nextSyncTime: 2025-11-21T01:00:00Z                     │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Cleanup                                                   │
│    - Delete snapshot                                         │
│    - Remove completed job pod                                │
└─────────────────────────────────────────────────────────────┘
```

### Restore Flow (On Missing PVC)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. App Deployment (PVC Missing)                             │
│    Flux reconciles app Kustomization                        │
│    ReplicationDestination checks for ${APP}-config PVC      │
│    Trigger: manual: restore-once                            │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Create Empty Destination PVC                             │
│    Name: ${APP}-config                                       │
│    Size: ${VOLSYNC_CAPACITY} (e.g., 10Gi)                   │
│    StorageClass: csi-cephfs-config-sc                       │
│    AccessMode: ReadWriteMany                                │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Launch Kopia Restore Job                                 │
│    Pod: volsync-dst-${APP}-${timestamp}                     │
│    Mounts:                                                   │
│      - Destination: ${APP}-config (read-write)              │
│      - Repository: kopia PVC (via repositoryPVC)            │
│      - Cache: kopia-cache-${APP} PVC                        │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Kopia Restore Process                                    │
│    - Connect to repository using ${APP}-volsync-secret      │
│    - Find latest snapshot for ${APP}                        │
│    - Read chunks from repository                            │
│    - Decompress and reassemble data                         │
│    - Write to destination PVC                               │
│    - Restore file ownership (UID/GID from moverSecurityContext)│
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Mark Restore Complete                                    │
│    ReplicationDestination.status.lastManualSync set         │
│    restore-once flag prevents future automatic restores     │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. App Pod Starts                                           │
│    HelmRelease references existingClaim: ${APP}-config      │
│    Pod mounts restored PVC with all previous data           │
│    Application starts with configuration intact             │
└─────────────────────────────────────────────────────────────┘
```

### Maintenance Jobs (With MutatingAdmissionPolicy)

When Kubernetes 1.34+ is available:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. VolSync Creates Maintenance Job                          │
│    Name pattern: kopia-maint-*                               │
│    Purpose: compaction, GC, verification                     │
│    Initially: No repository volume configured                │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. MutatingAdmissionPolicy Intercepts                       │
│    Matches on:                                               │
│      - Resource: Job (batch/v1)                             │
│      - Name prefix: kopia-maint-                            │
│      - Missing "repository" volume                           │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Automatic Volume Injection (JSONPatch)                   │
│    Adds to job spec:                                         │
│      volumes:                                                │
│        - name: repository                                    │
│          persistentVolumeClaim:                              │
│            claimName: kopia                                  │
│      volumeMounts:                                           │
│        - name: repository                                    │
│          mountPath: /repository                              │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Job Executes with Repository Access                      │
│    Connects to /repository                                   │
│    Performs maintenance (compact, GC, verify)                │
│    Updates repository metadata                               │
└─────────────────────────────────────────────────────────────┘
```

## Component Configuration

### VolSync Component Structure

Located at: `kubernetes/components/volsync/`

```
volsync/
├── kustomization.yaml              # Component definition
├── externalsecret.yaml             # Per-app Kopia credentials
├── kopia-repository-pvc.yaml       # Shared repository PVC (in app namespace)
├── replicationdestination.yaml     # Restore configuration
└── replicationsource.yaml          # Backup configuration
```

#### kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - ./externalsecret.yaml
  - ./kopia-repository-pvc.yaml
  # pvc.yaml commented out - ReplicationDestination manages PVC
  - ./replicationdestination.yaml
  - ./replicationsource.yaml
```

#### replicationsource.yaml (Backup)
Key configurations:
- **Schedule**: `0 * * * *` (every hour)
- **Source PVC**: `${APP}-config`
- **Copy Method**: `Snapshot` (uses CSI snapshots)
- **Compression**: `zstd-fastest`
- **Parallelism**: `2` streams
- **Retention**: 24 hourly, 7 daily snapshots
- **Repository**: Points to `${APP}-volsync-secret`
- **Storage**: Uses `${VOLSYNC_STORAGECLASS}` from app Kustomization

#### replicationdestination.yaml (Restore)
Key configurations:
- **Trigger**: `manual: restore-once` (only restores when PVC missing)
- **Destination PVC**: `${APP}-config`
- **Repository**: Points to `${APP}-volsync-secret`
- **Capacity**: `${VOLSYNC_CAPACITY}` from app Kustomization
- **Security Context**: Uses `${VOLSYNC_PUID}` and `${VOLSYNC_PGID}`

### App Kustomization Configuration

Each app using VolSync has this structure:

```yaml
# kubernetes/apps/default/emby/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
spec:
  components:
    - ../../../../components/volsync  # Include VolSync component

  dependsOn:
    - name: ceph-csi          # Ensure storage driver ready
      namespace: flux-system
    - name: volsync           # Ensure VolSync operator ready
      namespace: flux-system

  postBuild:
    substitute:
      APP: emby
      VOLSYNC_CAPACITY: 10Gi
      VOLSYNC_STORAGECLASS: csi-cephfs-config-sc
      VOLSYNC_SNAPSHOTCLASS: csi-cephfs-config-snapclass
      VOLSYNC_CACHE_SNAPSHOTCLASS: csi-cephfs-config-sc
```

### MutatingAdmissionPolicy Configuration

Located at: `kubernetes/apps/volsync-system/volsync/maintenance/mutatingadmissionpolicy.yaml`

Also saved to: `docs/volsync-kopia-mutatingadmissionpolicy.yaml`

Key features:
- **Match Conditions**: Jobs with name prefix `kopia-maint-*` and no `repository` volume
- **JSONPatch**: Injects `kopia` PVC as volume mount at `/repository`
- **Failure Policy**: `Fail` (ensures jobs don't run without proper config)
- **Requires**: Kubernetes 1.34+ (currently disabled on k8s 1.31)

## Repository Structure

### Kopia Repository Layout

```
/repository (in kopia PVC, volsync-system namespace)
├── kopia.repository.f          # Repository metadata
├── _log/                       # Operation logs
├── [content-hash]/             # Deduplicated data chunks
│   ├── [object-id]             # Compressed chunks
│   └── ...
└── [snapshots]/                # Snapshot metadata
    ├── emby/                   # Per-app snapshots
    │   ├── latest              # Latest snapshot reference
    │   └── [timestamp]         # Historical snapshots
    ├── immich/
    ├── sabnzbd/
    └── ...
```

### Deduplication Benefits

All apps share the same repository, enabling:
- **Cross-app deduplication**: Common files (e.g., base OS packages) stored once
- **Efficient storage**: Only delta changes backed up
- **Fast restores**: Cached chunks reused across apps

## Data Flow Example: Emby App

### Normal Operation (With Existing Data)

1. **Initial State**
   - Emby pod running
   - PVC `emby-config` contains media library database
   - Last backup: 1 hour ago

2. **Hourly Backup (01:00 UTC)**
   ```
   ReplicationSource triggers
   → CSI creates snapshot of emby-config
   → Kopia job starts
   → Reads snapshot, chunks data
   → Deduplicates against repository
   → Uploads only new/changed chunks
   → Writes snapshot metadata
   → Cleanup: Delete snapshot, remove job pod
   → Status updated: lastSyncTime, nextSyncTime
   ```

3. **Application Running**
   - User adds new media
   - Emby scans and updates database
   - Changes queued for next backup

### Disaster Recovery Scenario

1. **Disaster Occurs**
   ```
   kubectl delete pvc emby-config -n default
   # PVC deleted, all data gone
   ```

2. **Redeploy Application**
   ```
   flux reconcile kustomization emby -n flux-system
   ```

3. **Automatic Restore**
   ```
   ReplicationDestination detects missing PVC
   → Creates new empty emby-config PVC
   → Launches Kopia restore job
   → Connects to repository
   → Finds latest emby snapshot
   → Downloads and decompresses chunks
   → Writes data to new PVC
   → Sets file ownership (UID 1000, GID 1000)
   → Marks restore complete
   ```

4. **Application Starts**
   ```
   Emby HelmRelease deploys
   → Pod mounts restored emby-config PVC
   → Emby starts with full media library intact
   → Users can access media immediately
   ```

## Monitoring and Troubleshooting

### Check Backup Status

```bash
# View all ReplicationSources
kubectl get replicationsource -A

# Check specific app backup
kubectl describe replicationsource emby-src -n default

# View backup job logs
kubectl logs -n default -l volsync.backube/replication-source=emby-src
```

### Check Restore Status

```bash
# View all ReplicationDestinations
kubectl get replicationdestination -A

# Check specific app restore
kubectl describe replicationdestination emby-dst -n default

# View restore job logs
kubectl logs -n default -l volsync.backube/replication-destination=emby-dst
```

### Inspect Kopia Repository

```bash
# Connect to repository
kubectl run -n volsync-system kopia-cli --rm -it --restart=Never \
  --image=ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53 \
  --env="KOPIA_PASSWORD=$(kubectl get secret -n volsync-system kopia-secret -o jsonpath='{.data.KOPIA_PASSWORD}' | base64 -d)" \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "kopia",
      "image": "ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53",
      "stdin": true,
      "tty": true,
      "volumeMounts": [{
        "name": "repository",
        "mountPath": "/repository"
      }]
    }],
    "volumes": [{
      "name": "repository",
      "persistentVolumeClaim": {
        "claimName": "kopia"
      }
    }]
  }
}' -- /bin/sh

# Inside the pod:
kopia repository connect filesystem --path=/repository
kopia snapshot list
kopia snapshot list --all
kopia repository status
```

### Common Issues

#### Backup Failing: "Repository not found"

**Cause**: Kopia repository not initialized

**Fix**:
```bash
# Run initialization job (see initial setup section)
```

#### Restore Not Triggering

**Cause**: PVC already exists (restore-once behavior)

**Fix**: Delete PVC if you want to restore:
```bash
kubectl delete pvc ${APP}-config -n default
flux reconcile kustomization ${APP} -n flux-system
```

#### Maintenance Jobs Failing (Before k8s 1.34)

**Cause**: MutatingAdmissionPolicy not supported

**Status**: Expected, harmless. Maintenance will work after k8s upgrade.

## Performance Characteristics

### Backup Performance

- **Compression**: zstd-fastest (good ratio, minimal CPU)
- **Deduplication**: Block-level, cross-app
- **Parallelism**: 2 streams per backup
- **Snapshot Overhead**: Minimal (CSI copy-on-write)

### Typical Backup Times (from production)

| App       | PVC Size | First Backup | Incremental | Dedup Ratio |
|-----------|----------|--------------|-------------|-------------|
| emby      | 10Gi     | ~15min       | ~1min       | 65%         |
| immich    | 10Gi     | ~20min       | ~1.5min     | 70%         |
| plex      | 50Gi     | ~45min       | ~3min       | 60%         |

### Restore Performance

- **Full Restore**: ~50MB/s (depends on chunk cache)
- **With Warm Cache**: ~150MB/s
- **Network**: All local (CephFS), no bandwidth limits

## Security Considerations

### Encryption

- **At Rest**: Repository encrypted with `KOPIA_PASSWORD`
- **In Transit**: All local (in-cluster) communication
- **Secrets Management**: External Secrets Operator pulls from 1Password

### Access Control

- **Repository PVC**: Only accessible to volsync-system namespace
- **App Secrets**: Per-app ExternalSecret, namespace-scoped
- **RBAC**: VolSync operator has minimal required permissions

### Backup Integrity

- **Checksum Verification**: Kopia verifies all chunks on read/write
- **Snapshot Consistency**: CSI snapshots are crash-consistent
- **Retention Policy**: 24 hourly + 7 daily prevents accidental data loss

## Future Enhancements

### After Kubernetes 1.34 Upgrade

1. **Enable MutatingAdmissionPolicy**
   ```bash
   # Uncomment in kustomization
   # kubernetes/apps/volsync-system/volsync/maintenance/kustomization.yaml
   ```

2. **Benefits**
   - Automatic repository maintenance
   - Repository compaction for space efficiency
   - Garbage collection of orphaned chunks
   - Snapshot verification jobs

### Potential Improvements

- **Remote Replication**: Add S3 backend for off-site backups
- **Monitoring**: Prometheus metrics for backup success/failure
- **Alerting**: Alert on failed backups or restore operations
- **Scheduled Restores**: Test restore process monthly

## References

- **VolSync Documentation**: https://volsync.readthedocs.io/
- **Kopia Documentation**: https://kopia.io/docs/
- **MutatingAdmissionPolicy**: https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
- **Component Files**:
  - Volsync Component: `kubernetes/components/volsync/`
  - App Configurations: `kubernetes/apps/default/*/ks.yaml`
  - MutatingAdmissionPolicy: `docs/volsync-kopia-mutatingadmissionpolicy.yaml`
