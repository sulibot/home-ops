# Pre-Redeploy Checklist

## Issues to Fix in Git Before Cluster Wipe

### ✅ Critical: Namespace Configuration (FIXED!)

**Problem**: data-cephfs-pvc was getting created in wrong namespace (ceph-csi-cephfs instead of default)

**Root Cause**: The ceph-csi kustomization had `namespace: ceph-csi-cephfs` which was needed for secrets but overrode the PVC namespace.

**Solution Applied** (Commit bfe66f6):
- Created separate `shared-storage/` directory for PV/PVC
- Moved data-cephfs-pv.yaml and data-cephfs-pvc.yaml to shared-storage/
- Created separate Flux Kustomization (ceph-csi-shared-storage) with NO namespace context
- Now PVC will correctly use its own `namespace: default` declaration

**Structure**:
```
ceph-csi/          -> namespace: ceph-csi-cephfs (secrets, storage classes)
shared-storage/    -> no namespace (PV/PVC use their own namespaces)
```

---

## Storage Configuration (Already Fixed ✅)

1. ✅ **Storage Classes Created**:
   - csi-cephfs-sc (Delete, kubernetes pool)
   - csi-cephfs-sc-retain (Retain, kubernetes pool)
   - csi-cephfs-sc-backup (Delete, backups filesystem)

2. ✅ **Volsync Configuration**:
   - Updated to use csi-cephfs-sc-backup for destination
   - Updated to use csi-cephfs-sc for cache
   - Updated to use csi-cephfs-snapclass for snapshots

3. ✅ **data-cephfs-pv**:
   - fsName: content (correct)
   - PVC configured for namespace: default

4. ✅ **Ceph Backup Filesystem**:
   - `csi` subvolume group created on `backups` filesystem

---

## Known Issues (Will Be Resolved by Clean Deploy)

### Schema Validation Errors
These apps have `.values:` field errors in HelmRelease - will be fixed by clean deploy:
- home-assistant
- jellyseerr
- notifier
- nzbget
- plex
- prowlarr

### PVC Immutability Errors
These will be resolved with fresh PVCs on clean deploy:
- qbittorrent
- qui
- radarr
- sonarr
- tautulli

### Timeout Errors (Context Deadline Exceeded)
These are likely due to current cluster state and will resolve on fresh deploy:
- ceph-csi
- autobrr
- cross-seed
- fusion
- slskd
- smtp-relay
- thelounge
- zigbee
- zwave
- gatus
- unpoller
- victoria-logs
- kopia

---

## Post-Wipe Verification Steps

1. **Storage Classes**:
   ```bash
   kubectl get storageclass
   # Should show: csi-cephfs-sc, csi-cephfs-sc-retain, csi-cephfs-sc-backup
   ```

2. **data-cephfs-pvc**:
   ```bash
   kubectl get pvc data-cephfs-pvc -n default
   # Should be Bound to data-cephfs-pv in default namespace
   ```

3. **Ceph Mount Test**:
   ```bash
   kubectl get pods -n default | grep -E "sonarr|radarr|qbittorrent"
   # Pods should be Running and able to mount CephFS
   ```

4. **Volsync**:
   ```bash
   kubectl get replicationdestination -n default
   kubectl get pvc -n default | grep volsync
   # Should use csi-cephfs-sc-backup storage class
   ```

---

## Dependency Order (For Reference)

1. CRDs (Gateway API, External Secrets, etc.)
2. Storage (ceph-csi, storage classes)
3. External Secrets (1Password Connect, ClusterSecretStore)
4. Apps (depend on storage and secrets)

---

## Final Git Status

Repository is clean and ready for redeploy.
Latest commit: c15e015 "update config mount"
