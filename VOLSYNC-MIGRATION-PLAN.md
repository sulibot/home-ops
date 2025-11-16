# VolSync Migration to onedr0p Pattern

## Overview

This document outlines the migration from your current volsync-system to the onedr0p pattern, adapted for your Ceph storage (CephFS "backups" and RBD pool "rbd-backups").

## Prerequisites Completed

✅ **Talos MutatingAdmissionWebhook Enabled**

Updated `/talos/templates/talconfig.j2` to enable admission controllers including PodSecurity with namespace exemptions for:
- kube-system
- volsync-system
- actions-runner-system

**Next Steps for Talos:**
```bash
# Regenerate Talos configs
cd talos
# Your build process here to regenerate from template

# Apply to control plane nodes
talosctl apply-config -n solcp01 --file clusters/cluster-101/cluster-101-solcp01.yaml
talosctl apply-config -n solcp02 --file clusters/cluster-101/cluster-101-solcp02.yaml
talosctl apply-config -n solcp03 --file clusters/cluster-101/cluster-101-solcp03.yaml

# Verify API server restarted with new config
kubectl get pods -n kube-system -l component=kube-apiserver
```

## Current State Analysis

### What You Have (Good!)
- ✅ VolSync operator deployed (perfectra1n fork v0.16.12)
- ✅ Kopia server with UI
- ✅ MutatingAdmissionPolicy for auto-injecting Kopia PVC
- ✅ KopiaMaintenance scheduled (daily at 3:30 AM)
- ✅ Grafana dashboard + Prometheus rules
- ✅ Component structure in `/kubernetes/manifests/components/volsync/`
- ✅ Ceph storage configured with dedicated backup pools

### What Needs Adjustment
- 🔧 Component defaults use wrong storage classes
- 🔧 ReplicationDestination commented out
- 🔧 Storage class references need update for Ceph

## Storage Strategy

### Kopia Repository PVC
**Recommendation: CephFS "backups"**

```yaml
# kubernetes/apps/volsync-system/kopia/app/kopia-repository-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kopia
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: csi-cephfs-backups-sc  # ← Use CephFS backups
  resources:
    requests:
      storage: 100Gi  # ← Increase from 1Gi
```

**Why CephFS "backups":**
- ✅ ReadWriteMany - Multiple backup jobs can run simultaneously
- ✅ Dedicated filesystem for backups (isolation)
- ✅ Centralized repository accessible to all volsync movers
- ✅ Native CephFS snapshots supported

### Application PVC Storage Classes

**For most apps (configs, databases):**
```yaml
VOLSYNC_STORAGECLASS: csi-cephfs-config-sc
VOLSYNC_SNAPSHOTCLASS: csi-cephfs-config-snapclass
VOLSYNC_ACCESSMODES: ReadWriteMany
```

**For RBD-backed apps (VMs, large databases):**
```yaml
VOLSYNC_STORAGECLASS: csi-rbd-rbd-vm-sc
VOLSYNC_SNAPSHOTCLASS: csi-rbd-rbd-vm-snapclass
VOLSYNC_ACCESSMODES: ReadWriteOnce
```

## Migration Steps

### Step 1: Update Component Templates

**File: `/kubernetes/manifests/components/volsync/replicationsource.yaml`**

Change defaults from:
```yaml
storageClassName: "${VOLSYNC_STORAGECLASS:=ceph-block}"
accessModes:
  - "${VOLSYNC_ACCESSMODES:=ReadWriteOnce}"
volumeSnapshotClassName: "${VOLSYNC_SNAPSHOTCLASS:=csi-ceph-blockpool}"
```

To:
```yaml
storageClassName: "${VOLSYNC_STORAGECLASS:=csi-cephfs-config-sc}"
accessModes:
  - "${VOLSYNC_ACCESSMODES:=ReadWriteMany}"
volumeSnapshotClassName: "${VOLSYNC_SNAPSHOTCLASS:=csi-cephfs-config-snapclass}"
cacheStorageClassName: "${VOLSYNC_CACHE_STORAGECLASS:=csi-cephfs-config-sc}"
```

**File: `/kubernetes/manifests/components/volsync/kustomization.yaml`**

Uncomment:
```yaml
resources:
  - ./externalsecret.yaml
  - ./kopia-repository-pvc.yaml
  - ./pvc.yaml
  - ./replicationdestination.yaml  # ← Uncomment this
  - ./replicationsource.yaml
```

### Step 2: Increase Kopia Repository Size

```bash
# Check current usage
kubectl get pvc -n volsync-system kopia

# Edit PVC to increase size
kubectl edit pvc -n volsync-system kopia
# Change: storage: 1Gi → storage: 100Gi

# Verify expansion
kubectl get pvc -n volsync-system kopia -w
```

### Step 3: Test with One App

**Example: Enable volsync for `mosquitto`**

Edit `/kubernetes/apps/default/mosquitto/ks.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: mosquitto
  namespace: flux-system
spec:
  components:
    - ../../../../components/volsync  # ← Add this
  dependsOn:
    - name: external-secrets
      namespace: flux-system
    - name: onepassword
      namespace: flux-system
    - name: ceph-csi
      namespace: flux-system
  interval: 1h
  path: kubernetes/manifests/apps/default/mosquitto/app
  postBuild:
    substitute:
      APP: mosquitto                                    # ← Add these
      VOLSYNC_CAPACITY: 1Gi                            # ← substitutions
      VOLSYNC_STORAGECLASS: csi-cephfs-config-sc       # ←
      VOLSYNC_SNAPSHOTCLASS: csi-cephfs-config-snapclass  # ←
      VOLSYNC_PUID: "1000"                             # ← Match app user
      VOLSYNC_PGID: "1000"                             # ←
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: default
  wait: false
```

**Verify:**
```bash
# Check resources created
kubectl get replicationsource -n default mosquitto-src
kubectl get externalsecret -n default mosquitto-volsync
kubectl get secret -n default mosquitto-volsync-secret

# Watch first backup
kubectl logs -n default -l app.kubernetes.io/created-by=volsync --tail=100 -f

# Check Kopia repository
kubectl port-forward -n volsync-system svc/kopia 8080:80
# Open http://localhost:8080
```

### Step 4: Roll Out to Additional Apps

**Priority Order:**

1. **Low-risk apps** (easy to restore, not critical):
   - mosquitto
   - notifier
   - smtp-relay

2. **Medium-risk apps** (important but recoverable):
   - sonarr, radarr, prowlarr, lidarr
   - plex, emby
   - home-assistant

3. **High-value apps** (critical data):
   - immich
   - cloudnative-pg databases
   - grafana

**For each app:**
1. Add volsync component to ks.yaml
2. Configure postBuild substitutions
3. Commit and let Flux reconcile
4. Verify backup runs successfully
5. Test restore procedure (in test namespace if possible)

### Step 5: Configure Namespace Annotations

Every namespace using volsync needs this annotation:

```bash
# Add to each namespace manifest
kubectl annotate namespace default volsync.backube/privileged-movers="true"
kubectl annotate namespace observability volsync.backube/privileged-movers="true"
# etc.
```

Or add to namespace YAML:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: default
  annotations:
    volsync.backube/privileged-movers: "true"
```

## Component Template Reference

### ReplicationSource Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP` | (required) | App name, e.g., "mosquitto" |
| `VOLSYNC_CAPACITY` | 5Gi | Size of temporary snapshot volumes |
| `VOLSYNC_STORAGECLASS` | csi-cephfs-config-sc | Storage class for app PVC |
| `VOLSYNC_ACCESSMODES` | ReadWriteMany | Access mode for PVC |
| `VOLSYNC_SNAPSHOTCLASS` | csi-cephfs-config-snapclass | Snapshot class |
| `VOLSYNC_CACHE_STORAGECLASS` | csi-cephfs-config-sc | Cache storage class |
| `VOLSYNC_CACHE_CAPACITY` | 5Gi | Cache volume size |
| `VOLSYNC_PUID` | 1000 | User ID for mover pod |
| `VOLSYNC_PGID` | 1000 | Group ID for mover pod |

### ExternalSecret Variables

| Variable | Description |
|----------|-------------|
| `APP` | App name - creates secret `${APP}-volsync-secret` |

Creates secret with keys:
- `KOPIA_REPOSITORY`: `filesystem:///repository`
- `KOPIA_PASSWORD`: From 1Password

## Backup Schedule & Retention

### Default Configuration

**Schedule:** Hourly (every hour at :00)
```yaml
trigger:
  schedule: "0 * * * *"
```

**Retention Policy:**
- 24 hourly snapshots (1 day)
- 7 daily snapshots (1 week)

**Compression:** zstd-fastest

### Maintenance

Kopia maintenance runs daily at 3:30 AM:
```yaml
# kubernetes/apps/volsync-system/volsync/maintenance/kopiamaintenance.yaml
spec:
  schedule: "30 3 * * *"
```

This compacts the repository and removes orphaned data.

## Disaster Recovery

### Restore from Backup

1. **Trigger ReplicationDestination:**
   ```bash
   kubectl patch replicationdestination -n default mosquitto-dst \
     --type merge \
     --patch "{\"spec\":{\"trigger\":{\"manual\":\"restore-$(date +%s)\"}}}"
   ```

2. **Wait for PVC creation:**
   ```bash
   kubectl get pvc -n default mosquitto-config -w
   ```

3. **Verify data:**
   ```bash
   kubectl run -it --rm debug --image=busybox --restart=Never -- sh
   # Mount PVC and check contents
   ```

4. **Update app to use restored PVC:**
   - App should reference `mosquitto-config` PVC
   - Restart pod to mount restored data

### Full Namespace Restore

If you need to restore an entire namespace:

1. Create namespace with annotation
2. For each app, trigger ReplicationDestination
3. Wait for all PVCs to populate
4. Deploy apps pointing to restored PVCs
5. Verify functionality

## Monitoring & Alerting

### Prometheus Metrics

VolSync exposes metrics at:
```
volsync_replication_source_success
volsync_replication_source_duration_seconds
volsync_replication_source_last_successful_timestamp
```

### Grafana Dashboard

Already configured in:
```
kubernetes/apps/volsync-system/volsync/app/grafanadashboard.yaml
```

### Alerts

Configured in:
```
kubernetes/apps/volsync-system/volsync/app/prometheusrule.yaml
```

Alerts for:
- Backup failures
- Long-running backups
- Stale backups (no backup in 24h)

## Troubleshooting

### Issue: ReplicationSource Stuck in "Idle"

```bash
# Check secret exists
kubectl get secret -n <namespace> <app>-volsync-secret

# Verify Kopia PVC mounted
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Check mover pod logs
kubectl logs -n <namespace> -l app.kubernetes.io/created-by=volsync
```

### Issue: "Permission Denied" in Mover Pod

```bash
# Check namespace annotation
kubectl get ns <namespace> -o yaml | grep volsync.backube/privileged-movers

# Verify PVC ownership matches moverSecurityContext
kubectl exec -n <namespace> <pod> -- ls -la /data
```

### Issue: Snapshot Creation Fails

```bash
# Verify snapshot class exists
kubectl get volumesnapshotclass <snapshot-class>

# Check CSI driver
kubectl get csidriver cephfs.csi.ceph.com -o yaml

# Test manual snapshot
kubectl create -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
  namespace: default
spec:
  volumeSnapshotClassName: csi-cephfs-config-snapclass
  source:
    persistentVolumeClaimName: <pvc-name>
EOF
```

### Issue: Kopia Repository Errors

```bash
# Access Kopia UI
kubectl port-forward -n volsync-system svc/kopia 8080:80
# Open http://localhost:8080

# Or use CLI
kubectl exec -it -n volsync-system <kopia-pod> -- \
  kopia repository status --config-file=/config/repository.config
```

## Migration Checklist

### Pre-Migration
- [x] Enable MutatingAdmissionWebhook in Talos
- [ ] Regenerate and apply Talos configs
- [ ] Verify API server includes admission controllers
- [ ] Update component template defaults
- [ ] Increase Kopia repository PVC to 100Gi
- [ ] Verify snapshot classes functional

### Migration
- [ ] Test with low-risk app (mosquitto)
- [ ] Verify first backup completes
- [ ] Test restore procedure
- [ ] Roll out to 5 more apps
- [ ] Monitor for issues
- [ ] Continue progressive rollout

### Post-Migration
- [ ] All apps have volsync enabled
- [ ] Backups running hourly
- [ ] Prometheus alerts configured
- [ ] Grafana dashboard showing metrics
- [ ] Kopia maintenance running successfully
- [ ] Disaster recovery procedure documented and tested

## Next Steps

1. **Apply Talos Configuration:**
   ```bash
   cd talos
   # Regenerate configs from template
   # Apply to control plane nodes
   ```

2. **Update Component Templates:**
   - Update storage class defaults in replicationsource.yaml
   - Uncomment replicationdestination.yaml in kustomization.yaml

3. **Test with One App:**
   - Enable volsync for mosquitto
   - Verify backup runs
   - Test restore

4. **Progressive Rollout:**
   - Add 5 apps per day
   - Monitor for issues
   - Adjust as needed

## Resources

- **Component Location:** `/kubernetes/manifests/components/volsync/`
- **VolSync Operator:** `/kubernetes/apps/volsync-system/volsync/`
- **Kopia Server:** `/kubernetes/apps/volsync-system/kopia/`
- **Documentation:** This file

## Summary

Your current setup is already very close to onedr0p's pattern! The main changes needed are:

1. ✅ Enable MutatingAdmissionWebhook in Talos (DONE)
2. Update component defaults for Ceph storage classes
3. Increase Kopia repository PVC size
4. Enable volsync for applications progressively

The MutatingAdmissionPolicy auto-injection is already working, which is the clever part of onedr0p's approach. You just need to adapt the storage class references to match your Ceph configuration.

---

**Migration by:** Claude Code
**Date:** 2025-11-16
**Pattern:** onedr0p/home-ops volsync
**Status:** Ready to Execute
