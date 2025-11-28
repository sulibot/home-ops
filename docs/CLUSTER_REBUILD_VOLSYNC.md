# Cluster Rebuild - Volsync Kopia Repository Recovery

This document describes how to reclaim the Kopia repository PVC after rebuilding the Kubernetes cluster while preserving the Ceph cluster.

## Prerequisites

- Ceph cluster remains intact (only Kubernetes was rebuilt)
- CephFS subvolume ID was saved before destroying the old cluster
- Storage class `csi-cephfs-backups-sc` has `reclaimPolicy: Retain`

## Step 1: Save Subvolume ID (Before Destroying Old Cluster)

**CRITICAL:** Run this command on the OLD cluster BEFORE destroying it:

```bash
# Get the CephFS subvolume ID for the Kopia repository
kubectl get pv $(kubectl get pvc kopia -n default -o jsonpath='{.spec.volumeName}') \
  -o jsonpath='{.spec.csi.volumeHandle}'
```

**Example output:**
```
0001-0024-407036f5-1f73-44ff-ba81-1f219b7a8a64-000000000000000b-841e604c-1dd5-4a09-8763-84e672d78c4e
```

**Save this ID in a safe place** (e.g., password manager, notebook, etc.)

## Step 2: Verify Subvolume Exists in Ceph (After Cluster Rebuild)

After rebuilding Kubernetes and deploying ceph-csi, verify the subvolume still exists:

```bash
# SSH to a Ceph mon node
ssh root@<ceph-mon-host>

# List subvolumes in the backups filesystem
ceph fs subvolume ls backups csi

# You should see the subvolume ID from Step 1 in the list
```

## Step 3: Create PV Manifest

Create a PersistentVolume pointing to the existing subvolume:

**File:** `kopia-repository-pv.yaml`

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kopia-repository-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: csi-cephfs-backups-sc
  csi:
    driver: cephfs.csi.ceph.com
    # REPLACE THIS WITH YOUR SAVED SUBVOLUME ID FROM STEP 1
    volumeHandle: 0001-0024-407036f5-1f73-44ff-ba81-1f219b7a8a64-000000000000000b-841e604c-1dd5-4a09-8763-84e672d78c4e
    volumeAttributes:
      clusterID: 407036f5-1f73-44ff-ba81-1f219b7a8a64
      fsName: backups
      storage.kubernetes.io/csiProvisionerIdentity: "cephfs.csi.ceph.com"
    nodeStageSecretRef:
      name: csi-ceph-admin-secret
      namespace: ceph-csi
```

## Step 4: Create PVC Manifest

Create a PersistentVolumeClaim that binds to the PV:

**File:** `kopia-repository-pvc.yaml`

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kopia
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: csi-cephfs-backups-sc
  volumeName: kopia-repository-pv
  resources:
    requests:
      storage: 20Gi
```

## Step 5: Apply Manifests and Verify

**Important:** Apply in order - PV first, then PVC

```bash
# Apply PV
kubectl apply -f kopia-repository-pv.yaml

# Verify PV is Available
kubectl get pv kopia-repository-pv
# Expected: STATUS = Available

# Apply PVC
kubectl apply -f kopia-repository-pvc.yaml

# Verify PVC is Bound
kubectl get pvc kopia -n default
# Expected: STATUS = Bound

# Verify it bound to the correct PV
kubectl get pvc kopia -n default -o jsonpath='{.spec.volumeName}'
# Expected: kopia-repository-pv
```

## Step 6: Let Flux Deploy Kopia

Once the PVC is bound, Flux can deploy the Kopia application:

```bash
# Reconcile the kopia kustomization
flux reconcile ks kopia --with-source

# Wait for Kopia pod to be running
kubectl get pods -n default -l app.kubernetes.io/name=kopia

# Check Kopia logs
kubectl logs -n default -l app.kubernetes.io/name=kopia -f
```

**Expected log output:**
- Repository connected successfully
- Web UI started on port 80
- Server mode enabled

## Step 7: Verify Repository Contents

Access the Kopia web UI and verify the repository contains backups:

```bash
# Port-forward to access Kopia UI
kubectl port-forward -n default svc/kopia-app 8080:80

# Open browser to http://localhost:8080
# Navigate to "Snapshots" section
# Verify snapshots exist for plex, radarr, etc.
```

## Step 8: Trigger Volsync Restores

Once Kopia is running and serving the repository via HTTP, Volsync ReplicationDestination will automatically restore data:

```bash
# Watch ReplicationDestination status
kubectl get replicationdestination -n default -w

# Check restore job logs for radarr
kubectl logs -n default -l volsync.backube/replication-destination=radarr-dst -f

# Verify data restored to PVC
kubectl exec -n default -it deployment/radarr -- ls -lah /config
```

## Troubleshooting

### PVC Stuck in Pending

**Symptoms:**
```bash
kubectl get pvc kopia -n default
# STATUS: Pending
```

**Causes:**
1. PV `volumeName` doesn't match PVC's `spec.volumeName`
2. Storage class mismatch
3. Wrong subvolume ID

**Fix:**
```bash
# Delete PVC and recreate with correct volumeName
kubectl delete pvc kopia -n default
kubectl apply -f kopia-repository-pvc.yaml
```

### Kopia Pod Crashes: "Repository Not Found"

**Symptoms:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=kopia
# ERROR: repository not found
```

**Causes:**
- Wrong subvolume ID (mounted empty volume)
- Subvolume deleted by Ceph cleanup

**Fix:**
1. Verify subvolume exists in Ceph (Step 2)
2. Check `volumeHandle` in PV matches saved ID
3. If subvolume deleted, restore from S3 weekly backup (disaster recovery)

### ReplicationDestination Cannot Connect

**Symptoms:**
```bash
kubectl logs -n default -l volsync.backube/replication-destination=plex-dst
# ERROR: cannot connect to http://kopia.default.svc.cluster.local
```

**Causes:**
- Kopia service not running
- Kopia not in server mode
- Network policy blocking traffic

**Fix:**
```bash
# Verify Kopia service exists
kubectl get svc kopia-app -n default

# Check Kopia is in server mode
kubectl logs -n default -l app.kubernetes.io/name=kopia | grep "server start"

# Test connectivity from another pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://kopia.default.svc.cluster.local
```

## Recovery Timeline

**Expected time from cluster rebuild to full restore:**

1. Deploy ceph-csi: ~2 minutes (Flux automatic)
2. Reclaim PV/PVC: ~5 minutes (manual steps 3-5)
3. Deploy Kopia: ~2 minutes (Flux automatic)
4. Deploy apps: ~3 minutes (Flux automatic)
5. Restore data: ~10-30 minutes (depends on backup size)

**Total: ~20-45 minutes**

## Important Notes

- **Always save subvolume ID before destroying cluster**
- **Verify PVC is bound before letting Flux deploy Kopia**
- **Test recovery procedure at least once before disaster**
- **S3 weekly backups are last resort** (out of scope for this procedure)

## Reference

Current repository subvolume ID (as of 2025-11-27):
```
0001-0024-407036f5-1f73-44ff-ba81-1f219b7a8a64-000000000000000b-841e604c-1dd5-4a09-8763-84e672d78c4e
```

Update this document when subvolume ID changes (e.g., after recreating repository PVC).
