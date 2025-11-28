# Cluster Rebuild - Volsync Kopia Repository Recovery

This document describes how to reclaim the Kopia repository PVC after rebuilding the Kubernetes cluster while preserving the Ceph cluster.

## Prerequisites

- Ceph cluster remains intact (only Kubernetes was rebuilt)
- CephFS subvolume ID was saved before destroying the old cluster
- Storage class `csi-cephfs-backups-sc` has `reclaimPolicy: Retain`

## Step 1: Get Subvolume ID from Git

The subvolume ID is stored in Git as a Kubernetes Secret, so you don't need to manually save it!

**File:** `kubernetes/apps/6-data/kopia/app/kopia-repository-subvolume-secret.yaml`

```bash
# View the saved subvolume ID from Git
cat kubernetes/apps/6-data/kopia/app/kopia-repository-subvolume-secret.yaml | grep volumeHandle
```

**Example output:**
```yaml
volumeHandle: "0001-0024-407036f5-1f73-44ff-ba81-1f219b7a8a64-000000000000000b-841e604c-1dd5-4a09-8763-84e672d78c4e"
```

**Note:** If you ever recreate the Kopia PVC, update this secret with the new subvolume ID:
```bash
# Get current subvolume ID
kubectl get pv $(kubectl get pvc kopia -n default -o jsonpath='{.spec.volumeName}') \
  -o jsonpath='{.spec.csi.volumeHandle}'

# Update the secret file and commit to Git
```

## Step 2: Verify Subvolume Exists in Ceph (After Cluster Rebuild)

After rebuilding Kubernetes and deploying ceph-csi, verify the subvolume still exists:

```bash
# SSH to a Ceph mon node
ssh root@<ceph-mon-host>

# List subvolumes in the backups filesystem
ceph fs subvolume ls backups csi

# You should see the subvolume ID from Step 1 in the list
```

## Step 3: Reclaim PV/PVC (Automated Script)

Use the automated script to reclaim the repository PV/PVC:

```bash
# Run the reclaim script
./scripts/reclaim-kopia-repository.sh
```

The script will:
1. Read the subvolume ID from Git (`kopia-repository-subvolume-secret.yaml`)
2. Verify ceph-csi is deployed
3. Create the PersistentVolume pointing to the existing subvolume
4. Create the PersistentVolumeClaim bound to the PV
5. Wait for PVC to become Bound

**Example output:**
```
=== Kopia Repository PV Reclaim Tool ===

Read from Git:
  Volume Handle: 0001-0024-407036f5-1f73-44ff-ba81-1f219b7a8a64-000000000000000b-841e604c-1dd5-4a09-8763-84e672d78c4e
  Cluster ID:    407036f5-1f73-44ff-ba81-1f219b7a8a64
  FS Name:       backups
  Storage Class: csi-cephfs-backups-sc

Creating PersistentVolume...
✓ PV created

Waiting for PV to become Available...
persistentvolume/kopia-repository-pv condition met

Creating PersistentVolumeClaim...
✓ PVC created

Waiting for PVC to become Bound...
persistentvolumeclaim/kopia condition met

=== Success! ===

Next steps:
  1. Let Flux deploy the Kopia application
  2. Verify Kopia connects to repository
  3. Check Volsync restores start working
```

### Manual Method (Alternative)

If you prefer to create manifests manually, see the script source at `scripts/reclaim-kopia-repository.sh` for the exact PV/PVC YAML templates.

## Step 4: Let Flux Deploy Kopia

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

## Step 5: Verify Repository Contents

Access the Kopia web UI and verify the repository contains backups:

```bash
# Port-forward to access Kopia UI
kubectl port-forward -n default svc/kopia-app 8080:80

# Open browser to http://localhost:8080
# Navigate to "Snapshots" section
# Verify snapshots exist for plex, radarr, etc.
```

## Step 6: Trigger Volsync Restores

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
