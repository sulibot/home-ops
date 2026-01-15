# VolSync Automatic Restore System

## Overview

This document describes the automatic restore system for Kubernetes applications using VolSync and Kopia. After a cluster rebuild, application data is automatically restored from backups without manual intervention.

## Architecture

### Components

1. **Kopia Repository**: Shared backup repository storing all application snapshots
2. **ReplicationDestination**: VolSync resource that triggers restore jobs
3. **Volume Populator**: Kubernetes feature that populates PVCs from VolSync snapshots
4. **Application PVCs**: Persistent volumes that automatically restore from VolSync

### Automatic Restore Flow

```
Cluster Rebuild
    ↓
Flux Reconciles VolSync Component
    ↓
ReplicationDestination Created (per app)
    ↓
VolSync Restore Job Starts
    ↓
Kopia Restores Data to Temp PVC
    ↓
VolumeSnapshot Created
    ↓
Application PVC Auto-Populates from Snapshot
    ↓
Application Pod Starts
```

## How It Works

### 1. ReplicationDestination Configuration

Each application has a `ReplicationDestination` that defines:
- Source identity (which backup to restore from)
- Kopia repository connection
- Restore capacity
- Snapshot creation

**Example**: `kubernetes/apps/applications/plex/app/replicationdestination.yaml`
```yaml
---
APP: plex
VOLSYNC_CAPACITY: 50Gi
```

This uses the template at `kubernetes/components/volsync/replicationdestination.yaml` which automatically:
- Creates a restore job pod
- Mounts the Kopia repository
- Restores data from the latest snapshot
- Creates a VolumeSnapshot of restored data

### 2. PVC Auto-Population

Application PVCs reference the ReplicationDestination via `dataSourceRef`:

**Example**: `kubernetes/components/volsync/pvc.yaml` (template)
```yaml
spec:
  dataSourceRef:
    kind: ReplicationDestination
    apiGroup: volsync.backube
    name: ${APP}-dst
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${VOLSYNC_STORAGECLASS}
  resources:
    requests:
      storage: ${VOLSYNC_CAPACITY}
```

When the PVC is created, Kubernetes automatically:
1. Waits for ReplicationDestination to complete
2. Finds the snapshot created by VolSync
3. Populates the PVC from the snapshot
4. Binds the PVC when population is complete

### 3. Application Startup

Application pods remain in `Pending` state until:
- ReplicationDestination completes restore
- Snapshot is created
- PVC is bound and populated
- All volumes are available

**No manual intervention required** - Kubernetes handles the entire flow automatically.

## Configured Applications

Applications with automatic restore enabled:

| Application | Namespace | Capacity | PVC Name |
|------------|-----------|----------|----------|
| Plex | default | 50Gi | plex-config |
| Prometheus | observability-stack | 10Gi | prometheus-config |
| *23 other apps* | various | various | *-config |

## Monitoring Restore Progress

### Check ReplicationDestination Status

```bash
# All apps
kubectl get replicationdestination -A

# Specific app
kubectl describe replicationdestination plex-dst -n default
```

**Expected status**:
- `Synchronizing: True` - Restore in progress
- `Synchronizing: False` - Restore complete
- `Reconciled: True` - VolSync has processed the resource

### Check VolumeSnapshots

```bash
# All snapshots
kubectl get volumesnapshot -A

# Filter by app
kubectl get volumesnapshot -n default | grep plex
```

**Expected output**: One snapshot per ReplicationDestination with status `Ready: true`

### Check PVC Status

```bash
# All PVCs
kubectl get pvc -A

# Specific PVCs
kubectl get pvc -n default plex-config
```

**Status progression**:
1. `Pending` - Waiting for ReplicationDestination
2. `Pending` - Populating from snapshot
3. `Bound` - Ready for use

### Check Application Pods

```bash
# All pods
kubectl get pods -A

# Specific app
kubectl get pod -n default -l app.kubernetes.io/name=plex
```

**Status progression**:
1. `Pending` - Waiting for PVC to bind
2. `ContainerCreating` - PVC bound, starting container
3. `Running` - Application started successfully

## Restore Timing

Typical restore times vary by data size:

- **Small apps** (< 1GB): 2-5 minutes
- **Medium apps** (1-10GB): 5-15 minutes
- **Large apps** (> 10GB): 15-60 minutes

**Total cluster restore time**: 30-90 minutes depending on parallelism and data size.

## Troubleshooting

### Restore Not Starting

**Symptom**: ReplicationDestination stays in pending state

**Check**:
```bash
# Check VolSync operator
kubectl get pods -n volsync-system

# Check ReplicationDestination events
kubectl describe replicationdestination <name> -n <namespace>

# Force Flux reconciliation
flux reconcile kustomization <app> -n flux-system
```

### Restore Job Failing

**Symptom**: VolSync restore pod in `Error` or `CrashLoopBackOff`

**Check**:
```bash
# Find restore pod
kubectl get pods -n <namespace> | grep volsync-dst

# Check logs
kubectl logs -n <namespace> volsync-dst-<app>-<hash>

# Common issues:
# - Kopia repository not accessible
# - Source snapshot not found
# - Insufficient storage
```

### PVC Stuck in Pending

**Symptom**: PVC remains `Pending` after ReplicationDestination completes

**Check**:
```bash
# Check PVC events
kubectl describe pvc <name> -n <namespace>

# Check snapshot exists
kubectl get volumesnapshot -n <namespace>

# Check storage class
kubectl get storageclass

# Common issues:
# - Snapshot not created
# - Storage class not available
# - CSI driver issues
```

### Pod Stuck in Pending

**Symptom**: Application pod stays `Pending` even after PVC is bound

**Check**:
```bash
# Check pod events
kubectl describe pod <name> -n <namespace>

# Common issues:
# - Node selector/affinity not satisfied
# - Resource constraints
# - Other volume mount issues (not VolSync-related)
```

## Manual Intervention (Break-Glass)

If automatic restore fails, you can manually create a PVC:

### Example: Plex Manual PVC

```bash
# Uncomment the manual PVC in kustomization.yaml
# kubernetes/apps/applications/plex/app/kustomization.yaml
# - ./manual-plex-config-pvc.yaml

# Apply manually
kubectl apply -f kubernetes/apps/applications/plex/app/manual-plex-config-pvc.yaml

# The manual PVC file creates an empty PVC that bypasses VolSync
# You can then manually restore data using Kopia CLI
```

**Note**: Manual PVCs are named `manual-<app>-config-pvc.yaml` and are commented out by default. They're only used for disaster recovery when VolSync fails.

## Configuration Files

### VolSync Component Template Files

- `kubernetes/components/volsync/replicationdestination.yaml` - Restore job template
- `kubernetes/components/volsync/replicationsource.yaml` - Backup job template
- `kubernetes/components/volsync/pvc.yaml` - PVC with auto-restore template
- `kubernetes/components/volsync/kustomization.yaml` - Component configuration

### Application-Specific Files

Each app with VolSync enabled has:
- `replicationdestination.yaml` - Restore config (sets APP and VOLSYNC_CAPACITY)
- `replicationsource.yaml` - Backup config
- `kustomization.yaml` - References VolSync component

**Example directory structure**:
```
kubernetes/apps/applications/plex/app/
├── kustomization.yaml                    # References volsync component
├── replicationdestination.yaml           # APP: plex, VOLSYNC_CAPACITY: 50Gi
├── replicationsource.yaml                # Backup schedule
├── manual-plex-config-pvc.yaml          # Break-glass PVC (commented out)
└── helmrelease.yaml                      # App deployment
```

## Adding VolSync to New Applications

To enable automatic backup/restore for a new application:

1. **Add VolSync component** to `kustomization.yaml`:
   ```yaml
   components:
     - ../../../../components/volsync
   ```

2. **Create `replicationdestination.yaml`**:
   ```yaml
   ---
   APP: myapp
   VOLSYNC_CAPACITY: 10Gi
   ```

3. **Create `replicationsource.yaml`**:
   ```yaml
   ---
   APP: myapp
   VOLSYNC_CAPACITY: 10Gi
   ```

4. **Optional: Create break-glass PVC** as `manual-myapp-config-pvc.yaml` and comment out in kustomization

5. **Ensure PVC name follows convention**: `<app>-config`

6. **Commit and push** - Flux will automatically configure backup/restore

## Network Configuration for Multus Applications

Some applications (Plex, Home Assistant) require additional VLAN network access via Multus. The cluster includes special network configuration for these apps:

### VLAN Trunk Configuration

Worker nodes have a second network interface (ens19) connected to vmbr0 for VLAN access:

**Terraform**: `terraform/infra/modules/cluster_core/main.tf:411-421`
```terraform
# net1 (ens19): VLAN trunk for Multus
# Only added to worker nodes (not control plane)
dynamic "network_device" {
  for_each = !each.value.control_plane ? [1] : []
  content {
    bridge  = "vmbr0"
    vlan_id = null  # No VLAN tagging at VM level
    mtu     = 1500
  }
}
```

**Multus NetworkAttachmentDefinitions**:
- `kubernetes/apps/networking/multus/networks/vlan30.yaml` - IoT network
- `kubernetes/apps/networking/multus/networks/vlan31.yaml` - Additional VLAN

These use macvlan on `ens19` with VLAN tagging to provide direct VLAN access to pods.

## References

- [VolSync Documentation](https://volsync.readthedocs.io/)
- [Kopia Documentation](https://kopia.io/docs/)
- [Kubernetes Volume Populators](https://kubernetes.io/blog/2022/05/16/volume-populators-beta/)
- [VOLSYNC_KOPIA_BACKUP_SYSTEM.md](./VOLSYNC_KOPIA_BACKUP_SYSTEM.md) - Detailed backup system design
- [VOLSYNC_AUTO_RESTORE_STATUS.md](./VOLSYNC_AUTO_RESTORE_STATUS.md) - Historical restore status tracking
