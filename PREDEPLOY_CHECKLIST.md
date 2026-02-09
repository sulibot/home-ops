# Pre-Redeploy Checklist - FINAL

## ✅ ALL ISSUES FIXED - READY FOR CLUSTER WIPE

### Latest Fix (Commit 4ed4139)

**Namespace Dependency Issue - RESOLVED**

Moved observability PV/PVC resources from `shared-storage/` to `apps/observability/_namespace/` so they are created AFTER the namespace exists.

**Deployment Order:**
1. `observability` namespace created
2. `cephfs-content-pv-observability` and `cephfs-content-pvc-observability` created
3. Observability apps can mount shared storage

---

## Storage Configuration Summary

### Storage Classes (Cluster-Wide)
```
cephfs-csi-sc          - Delete policy, kubernetes pool (regular volumes)
cephfs-csi-sc-retain   - Retain policy, kubernetes pool (important data)
cephfs-backup-sc   - Delete policy, backups filesystem (Volsync/Kopia)
```

### Shared CephFS Storage (40Ti)
**Default Namespace:**
- PV: `cephfs-content-pv`
- PVC: `cephfs-content-pvc`
- Location: `platform/storage/ceph-csi-cephfs/shared-storage/`

**Observability Namespace:**
- PV: `cephfs-content-pv-observability`
- PVC: `cephfs-content-pvc`
- Location: `apps/observability/_namespace/`

**Both mount the same CephFS path:**
- Filesystem: `content`
- Root Path: `/` (entire 40Ti volume)
- Access Mode: ReadWriteMany (RWX)

---

## Volsync Configuration

**Default Storage Classes:**
- `storageClassName`: `cephfs-backup-sc` (backup destination)
- `cacheStorageClassName`: `cephfs-csi-sc` (cache volumes)
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
# Expected: cephfs-csi-sc, cephfs-csi-sc-retain, cephfs-backup-sc
```

### 2. Verify PVCs in Correct Namespaces
```bash
kubectl get pvc -A | grep data-cephfs
# Expected:
# default         cephfs-content-pvc   Bound   cephfs-content-pv                40Ti   RWX
# observability   cephfs-content-pvc   Bound   cephfs-content-pv-observability  40Ti   RWX
```

### 3. Check Apps Can Mount Storage
```bash
kubectl get pods -n default | grep -E "sonarr|radarr|qbittorrent"
# Should be Running (not Pending with mount errors)
```

### 4. Verify Volsync Storage Classes
```bash
kubectl get pvc -n default | grep volsync
# Should show cephfs-backup-sc storage class
```

### 5. Verify Backups Are Running (CRITICAL)
```bash
# Check volsync pods are running (not stuck in Init)
kubectl get pods -n volsync-system
kubectl get pods -A | grep volsync-src | grep -v Completed | grep -v Running
# ⚠️ Should return empty - no stuck pods

# Verify backup jobs complete within 5 minutes
watch kubectl get jobs -A | grep volsync-src
# Jobs should transition: Running → Complete

# Check recent backup timestamps (after first hourly run)
kubectl get replicationsource -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.lastSyncTime}{"\n"}{end}'
# Should show recent timestamps (within last hour)

# Verify kopia repository is connected
kubectl logs -n volsync-system job/kopia-repository-connect
# Should show "Repository already connected" or "Repository connected successfully"
```

**⚠️ If backups are stuck:**
1. Check for pods in Init state >5min
2. Review Prometheus alerts (PodStuckInInit should fire)
3. Check volsync operator logs: `kubectl logs -n volsync-system deployment/volsync`
4. Verify no broken admission policies: `kubectl get mutatingadmissionpolicy,validatingadmissionpolicy`

---

## Git Repository Status

**Branch:** main
**Latest Commit:** aafa5449 - "feat(monitoring): Add alerts for pods stuck in Init state"

**Recent Changes:**
```
aafa5449 feat(monitoring): Add alerts for pods stuck in Init state
c59a49fc fix(volsync): Remove broken MutatingAdmissionPolicy blocking backups
3b249ab9 shrinking the subnetting the GUA subnet to /112
3e1122cc fix(bgp): Add pod CIDRs to FRR allowed_prefixes
11fe04ab fix(bgp): Add pod CIDRs to FRR allowed_prefixes
```

**Critical Fixes Applied:**
- ✅ Removed broken MutatingAdmissionPolicy that blocked volsync backups
- ✅ Added Prometheus alerts for pods stuck in Init state (prevents future silent failures)
- ✅ BGP configuration verified and working
- ✅ DNS resolution working (IPv4 and IPv6)

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
