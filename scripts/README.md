# Scripts Documentation

This directory contains operational scripts for managing the home-ops Kubernetes cluster.

## Disaster Recovery (DR) Scripts

These scripts are used to restore the cluster after a complete rebuild. Run them in order:

### DR-1: Check Readiness
**Script:** `dr-1-check-readiness.sh`

**Purpose:** Verify all prerequisites are met before starting restore process

**When to run:** Immediately after cluster rebuild, once Flux is deployed

**Checks:**
- ✅ Flux core components (flux-system)
- ✅ Essential kustomizations (cert-manager, external-secrets, ceph-csi, volsync)
- ✅ Storage classes available
- ✅ Ceph-CSI pods running
- ✅ Volsync operator running
- ✅ Volsync secrets created (from ExternalSecrets)

**Usage:**
```bash
./scripts/dr-1-check-readiness.sh
```

**Expected output:**
```
✅ READY: All prerequisites met!

Next step:
  ./scripts/dr-2-reclaim-kopia-repository.sh
```

---

### DR-2: Reclaim Kopia Repository
**Script:** `dr-2-reclaim-kopia-repository.sh`

**Purpose:** Reconnect to existing Kopia backup repository after cluster rebuild

**Prerequisites:**
- ✅ All infrastructure components Ready (verified by dr-1)
- ✅ CephFS CSI driver running

**What it does:**
1. Reads CephFS subvolume ID from `kubernetes/apps/6-data/kopia/app/kopia-repository-subvolume-secret.yaml`
2. Creates PersistentVolume pointing to existing subvolume
3. Creates PersistentVolumeClaim bound to that PV
4. Waits for PVC to become Bound

**Result:** `kopia` PVC (200Gi) in `default` namespace with all existing backups intact

**Usage:**
```bash
./scripts/dr-2-reclaim-kopia-repository.sh
```

**Expected output:**
```
✅ SUCCESS: Kopia Repository Reclaimed

PVC Status:
NAME    STATUS   VOLUME                 CAPACITY   ACCESS MODES   STORAGECLASS
kopia   Bound    kopia-repository-pv    200Gi      RWX            csi-cephfs-backups-sc

Next step:
  Wait 1-2 minutes for apps to reconcile, then run:
  ./scripts/dr-3-trigger-restores.sh
```

---

### DR-3: Trigger Restores
**Script:** `dr-3-trigger-restores.sh`

**Purpose:** Trigger Volsync restores for all 22 applications

**Prerequisites:**
- ✅ Kopia repository PVC reclaimed (verified automatically)
- ✅ ReplicationDestination resources exist (created by Flux)

**What it does:**
1. Patches all ReplicationDestination resources to trigger manual restore
2. Volsync starts restore jobs (one per app)
3. Each restore job:
   - Connects to Kopia repository
   - Restores latest snapshot to temp PVC
   - Creates VolumeSnapshot from restored data
4. Volume populator creates app config PVCs from snapshots

**Timeline:**
- **T+0:** Restore jobs start
- **T+5-10min:** Restore jobs complete, VolumeSnapshots created
- **T+10-15min:** All app config PVCs bound and ready

**Usage:**
```bash
./scripts/dr-3-trigger-restores.sh
```

**Expected output:**
```
✅ Triggered 22 restores at 20251201151637

To monitor progress in real-time:
  watch 'kubectl get jobs -n default | grep volsync-dst'
  watch 'kubectl get volumesnapshot -n default | grep dst-dest'
  watch 'kubectl get pvc -n default | grep config'

Expected timeline:
  - Now:        Restore jobs running
  - T+5-10min:  Restore jobs complete, VolumeSnapshots created
  - T+10-15min: All app config PVCs Bound and ready
```

---

### DR-4: Verify Restores
**Script:** `dr-4-verify-restores.sh`

**Purpose:** Verify all restores completed successfully

**When to run:** After dr-3, wait 10-15 minutes then run this

**What it checks:**
- ✅ All restore jobs completed successfully (no failures)
- ✅ All VolumeSnapshots created and ready
- ✅ All app config PVCs bound with correct sizes
- ✅ Total restored capacity matches expected (~236Gi)

**Usage:**
```bash
./scripts/dr-4-verify-restores.sh
```

**Expected output:**
```
✅ SUCCESS: All restores verified!

All app config PVCs are restored and ready.
Apps should now be starting automatically.

Disaster recovery complete! 🎉
```

---

## Complete DR Workflow

After a cluster rebuild, run these commands in order:

```bash
# 1. Wait for Flux to deploy (5-15 minutes)
watch flux get ks --all-namespaces

# 2. Check readiness
./scripts/dr-1-check-readiness.sh

# 3. Reclaim Kopia repository
./scripts/dr-2-reclaim-kopia-repository.sh

# 4. Wait 1-2 minutes, then trigger restores
sleep 120
./scripts/dr-3-trigger-restores.sh

# 5. Wait 10-15 minutes for restores to complete
sleep 600

# 6. Verify all restores completed
./scripts/dr-4-verify-restores.sh

# 7. Check apps are starting
kubectl get pods -n default
```

**Total time from cluster rebuild to apps running:** ~30-40 minutes

---

## Maintenance Scripts

These scripts are for day-to-day cluster operations.

### Reconcile All Apps
**Script:** `maint-reconcile-all-apps.sh`

**Purpose:** Force Flux to reconcile all application kustomizations

**When to use:**
- After making changes to app configurations
- To force update of all apps to latest Git revision
- After fixing issues with specific apps

**Usage:**
```bash
./scripts/maint-reconcile-all-apps.sh
```

---

### Cluster Status
**Script:** `maint-cluster-status.sh`

**Purpose:** Show status of all clusters

**Usage:**
```bash
./scripts/maint-cluster-status.sh
```

---

### Validate Cluster
**Script:** `maint-validate-cluster.sh`

**Purpose:** Validate cluster configuration consistency

**Usage:**
```bash
./scripts/maint-validate-cluster.sh
```

---

### Resolve Cluster
**Script:** `maint-resolve-cluster.sh`

**Purpose:** Resolve cluster directory from cluster name or ID

**Usage:**
```bash
./scripts/maint-resolve-cluster.sh cluster-101
```

---

## App Config PVC Sizes

The following PVC sizes are configured via `VOLSYNC_CAPACITY` in each app's `ks.yaml`:

| App               | Size  | App               | Size  |
|-------------------|-------|-------------------|-------|
| plex              | 50Gi  | filebrowser       | 10Gi  |
| home-assistant    | 25Gi  | lidarr            | 10Gi  |
| emby              | 15Gi  | overseerr         | 10Gi  |
| immich            | 15Gi  | radarr            | 10Gi  |
| redis             | 10Gi  | sonarr            | 10Gi  |
| tautulli          | 10Gi  | atuin             | 5Gi   |
| jellyseerr        | 5Gi   | mosquitto         | 5Gi   |
| slskd             | 5Gi   | nzbget            | 3Gi   |
| prowlarr          | 3Gi   | qbittorrent       | 3Gi   |
| sabnzbd           | 3Gi   | thelounge         | 3Gi   |
| autobrr           | 2Gi   | qui               | 2Gi   |

**Total:** ~236Gi for all app config volumes

---

## Kopia Repository

- **Size:** 200Gi
- **Location:** CephFS subvolume on `csi-cephfs-backups-sc`
- **Contains:** Backups for all 22 app config volumes
- **Retention:** 30 days
- **Expected usage:** 50-80Gi with deduplication and compression

The subvolume ID is saved in Git at:
`kubernetes/apps/6-data/kopia/app/kopia-repository-subvolume-secret.yaml`

This allows the repository to survive cluster rebuilds and be reclaimed using dr-2 script.

---

## Troubleshooting

### DR-1 fails: Components not Ready
**Issue:** Infrastructure components haven't finished deploying

**Solution:** Wait longer and run dr-1 again. Check Flux progress:
```bash
watch flux get ks --all-namespaces
```

---

### DR-2 fails: PVC won't bind
**Issue:** CephFS CSI driver not ready or subvolume doesn't exist

**Check CSI pods:**
```bash
kubectl get pods -n ceph-csi
```

**Check subvolume exists in Ceph:**
```bash
# SSH to Ceph cluster and verify subvolume exists
```

---

### DR-3: Restore jobs fail
**Issue:** Can't connect to Kopia repository or repository empty

**Check Kopia repository connection:**
```bash
kubectl logs -n default -l app.kubernetes.io/name=kopia
```

**Check backups exist:**
```bash
# From inside Kopia pod
kopia snapshot list --all
```

---

### DR-4: PVCs stuck in Pending
**Issue:** VolumeSnapshots not created or not ready

**Check VolumeSnapshot status:**
```bash
kubectl get volumesnapshot -n default | grep dst-dest
kubectl describe volumesnapshot <snapshot-name> -n default
```

**Check restore job logs:**
```bash
kubectl logs job/volsync-dst-<app>-dst -n default
```

---

## Script Dependencies

```
dr-1-check-readiness.sh
  └─> dr-2-reclaim-kopia-repository.sh
       └─> dr-3-trigger-restores.sh
            └─> dr-4-verify-restores.sh
```

Each script checks its prerequisites and will fail with helpful error messages if requirements aren't met.
