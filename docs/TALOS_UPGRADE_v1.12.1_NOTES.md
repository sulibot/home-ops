# Talos v1.12.1 Upgrade Notes

## Upgrade Date: 2026-01-14

## Reason for Upgrade

Upgrading from Talos v1.11.5 to v1.12.1 to fix a critical CephFS kernel client deadlock bug.

### The Bug
- **Kernel**: Linux 6.12.57 (in Talos v1.11.5)
- **Issue**: CephFS kernel client hangs indefinitely when mounting volumes
- **Symptoms**:
  - `mount.ceph` processes stuck in D state (uninterruptible sleep)
  - VolSync restore pods stuck in ContainerCreating
  - Mount operations timeout after 6+ minutes
- **Root Cause**: Linux Kernel 6.12 regression in CephFS client with IPv6 and msgr2
- **Fix**: Linux Kernel 6.18.2 (in Talos v1.12.1) includes upstream CephFS fixes

### References
- Talos Release: https://github.com/siderolabs/talos/releases/tag/v1.12.1
- Kernel upgrade: 6.12.57-talos → 6.18.2-talos
- Analysis provided by Gemini 3 Pro Preview

## Changes Made During Troubleshooting

### VolSync/Kopia Changes to Revert After Upgrade

The following changes were made while troubleshooting and should be **reverted after the Talos upgrade succeeds**:

1. **Removed `repositoryPVC` field** from VolSync ReplicationDestination template:
   - File: `kubernetes/components/volsync/replicationdestination.yaml`
   - Change: Added line 20 `repositoryPVC: "kopia"`
   - Commit: `e12f8689` - "fix(volsync): add repositoryPVC to enable Kopia restore access"
   - **Action**: This was incorrectly added (field doesn't exist in CRD). Revert this commit after upgrade.

2. **Documentation created**:
   - File: `docs/VOLSYNC_PVC_RESTORE_FIX.md`
   - Contains manual trigger restoration guide
   - **Action**: Can keep for reference, but the kernel fix should make manual triggers unnecessary

### Git Commits to Revert

```bash
# After successful Talos upgrade and verification that CephFS mounts work:
git revert e12f8689  # Revert repositoryPVC change
```

## Upgrade Process

Follow the process in `terraform/infra/live/clusters/cluster-101/UPGRADE_GUIDE.md` - Scenario 3: Talos Version Upgrade

### Step 1: Update Versions
- ✅ Updated `terraform/infra/live/common/versions.hcl`
  - `talos_version`: v1.11.5 → v1.12.1
  - `extension_version`: v1.11.5 → v1.12.1

### Step 2: Rebuild Images
```bash
cd terraform/infra/live/clusters/cluster-101/images
terragrunt run-all apply
```

### Step 3: Update Machine Configs
```bash
cd ../cluster/2-machine-config-generate
terragrunt apply

cd ../3-cluster-bootstrap
terragrunt apply
```

### Step 4: Upgrade Nodes
```bash
# Upgrade control plane nodes first
talosctl --nodes solcp01,solcp02,solcp03 upgrade \
  --image ghcr.io/sulibot/sol-talos-installer-frr:v1.12.1 \
  --preserve

# Wait for control plane to stabilize, then upgrade workers
talosctl --nodes solwk01,solwk02,solwk03 upgrade \
  --image ghcr.io/sulibot/sol-talos-installer-frr:v1.12.1 \
  --preserve
```

## Post-Upgrade Verification

### 1. Verify Kernel Version
```bash
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}'
# Expected: 6.18.2-talos
```

### 2. Test CephFS Mount
```bash
# Create a test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs-mount
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: csi-cephfs-config-sc
EOF

# Create a test pod
kubectl run test-cephfs --image=nginx --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"test","persistentVolumeClaim":{"claimName":"test-cephfs-mount"}}],"containers":[{"name":"nginx","image":"nginx","volumeMounts":[{"name":"test","mountPath":"/mnt/test"}]}]}}'

# Check if pod starts quickly (should be < 30 seconds)
kubectl get pod test-cephfs -w

# Cleanup
kubectl delete pod test-cephfs
kubectl delete pvc test-cephfs-mount
```

### 3. Restore VolSync Functionality
```bash
# Recreate all ReplicationDestinations that were deleted
flux reconcile kustomization apps -n flux-system

# Monitor restore pods
watch kubectl get pods -n default -l app.kubernetes.io/created-by=volsync
```

### 4. Revert Troubleshooting Changes
```bash
# Revert the repositoryPVC change
git revert e12f8689

# Push the revert
git push
```

## Rollback Plan

If the upgrade causes issues:

```bash
# Roll back to Talos v1.11.5
talosctl --nodes NODE upgrade \
  --image ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5 \
  --preserve
```

However, rolling back will **reintroduce the CephFS mount bug**. If rollback is needed, the only workaround is to use FUSE mounter (see `gemini-prompt.md` for details).

## Expected Outcome

After successful upgrade:
- ✅ CephFS mounts complete in < 10 seconds (not 6+ minutes)
- ✅ VolSync restore pods start successfully
- ✅ All 23 applications can be restored from Kopia backups
- ✅ No more `mount.ceph` processes stuck in D state
- ✅ Kernel CephFS client works reliably with IPv6 Ceph monitors
