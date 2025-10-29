# Pre-Redeploy Checklist - FINAL

## ✅ ALL ISSUES FIXED - READY FOR CLUSTER WIPE

### Latest Fix (Commit 4ed4139)

**Namespace Dependency Issue - RESOLVED**

Moved observability PV/PVC resources from `shared-storage/` to `apps/observability/_namespace/` so they are created AFTER the namespace exists.

**Deployment Order:**
1. `observability` namespace created
2. `data-cephfs-pv-observability` and `data-cephfs-pvc-observability` created
3. Observability apps can mount shared storage

---

## Storage Configuration Summary

### Storage Classes (Cluster-Wide)
```
csi-cephfs-sc          - Delete policy, kubernetes pool (regular volumes)
csi-cephfs-sc-retain   - Retain policy, kubernetes pool (important data)
csi-cephfs-sc-backup   - Delete policy, backups filesystem (Volsync/Kopia)
```

### Shared CephFS Storage (40Ti)
**Default Namespace:**
- PV: `data-cephfs-pv`
- PVC: `data-cephfs-pvc`
- Location: `platform/storage/ceph-csi-cephfs/shared-storage/`

**Observability Namespace:**
- PV: `data-cephfs-pv-observability`
- PVC: `data-cephfs-pvc`
- Location: `apps/observability/_namespace/`

**Both mount the same CephFS path:**
- Filesystem: `content`
- Root Path: `/` (entire 40Ti volume)
- Access Mode: ReadWriteMany (RWX)

---

## Volsync Configuration

**Default Storage Classes:**
- `storageClassName`: `csi-cephfs-sc-backup` (backup destination)
- `cacheStorageClassName`: `csi-cephfs-sc` (cache volumes)
- `volumeSnapshotClassName`: `csi-cephfs-snapclass` (snapshots)

---

## Ceph Requirements Verified

- ✅ `csi` subvolume group created on `backups` filesystem
- ✅ Backup storage class tested and working
- ✅ All storage classes use correct CephFS filesystems

---

## Post-Wipe Verification Commands

### 1. Check Storage Classes
```bash
kubectl get storageclass
# Expected: csi-cephfs-sc, csi-cephfs-sc-retain, csi-cephfs-sc-backup
```

### 2. Verify PVCs in Correct Namespaces
```bash
kubectl get pvc -A | grep data-cephfs
# Expected:
# default         data-cephfs-pvc   Bound   data-cephfs-pv                40Ti   RWX
# observability   data-cephfs-pvc   Bound   data-cephfs-pv-observability  40Ti   RWX
```

### 3. Check Apps Can Mount Storage
```bash
kubectl get pods -n default | grep -E "sonarr|radarr|qbittorrent"
# Should be Running (not Pending with mount errors)
```

### 4. Verify Volsync Storage Classes
```bash
kubectl get pvc -n default | grep volsync
# Should show csi-cephfs-sc-backup storage class
```

---

## Git Repository Status

**Branch:** main  
**Latest Commit:** 4ed4139 - "Fix namespace dependency: move observability PV/PVC to observability kustomization"

**Recent Changes:**
```
4ed4139 Fix namespace dependency: move observability PV/PVC to observability kustomization
1c87d2f Add shared CephFS storage for observability namespace
bfe66f6 PROPER FIX: Move data-cephfs-pv/pvc to separate kustomization
```

---

## ✅ CLUSTER WIPE READY

All configuration issues have been resolved. The repository is clean and ready for cluster redeploy.

**Key Points:**
- ✅ PVCs will deploy to correct namespaces
- ✅ No namespace override issues
- ✅ Proper dependency ordering
- ✅ Both default and observability namespaces will access shared 40Ti media storage
- ✅ Volsync will use CephFS storage classes
- ✅ All storage configuration tested
