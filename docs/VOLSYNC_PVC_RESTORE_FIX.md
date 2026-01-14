# Volsync PVC Restore Fix Plan

## Problem Statement

Volsync ReplicationDestination restore jobs are failing with:
```
ERROR can't connect to storage: cannot access storage path: stat /kopia: no such file or directory
ERROR unable to create directory: mkdir /kopia: read-only file system
```

**Root Cause:** ReplicationDestination template is missing `repositoryPVC: "kopia"` configuration, so restore job pods don't mount the Kopia repository PVC, making backups inaccessible.

**Impact:** All PVC restores fail, applications start with empty data instead of restored backups.

---

## Current State

### What's Working ✅
- Volsync operator deployed (v0.16.12)
- Kopia repository PVC created per namespace (1Gi, CephFS backups storage class)
- ReplicationSource backup jobs working (apps are being backed up)
- ExternalSecret providing Kopia credentials
- Component structure properly configured

### What's Broken ❌
- ReplicationDestination restore jobs fail (no repository access)
- PVCs created empty instead of restored from backup
- Applications start with fresh/empty configuration

### Evidence from Current Cluster

**Plex:**
```bash
$ kubectl exec -n default deploy/plex -- ls -la /config/
drwxrwsr-x 3 root   ubuntu  1 Nov 26 23:53 Library
# Nearly empty - should have full Plex database
```

**Radarr:**
```bash
$ kubectl exec -n default deploy/radarr -- ls -la /config/
-rw-rw-r-- 1 1000 1000  950272 Nov 27 05:35 radarr.db
# Has some data but likely fresh initialization, not restored backup
```

**Volsync Job Logs:**
```bash
$ kubectl logs -n default job/volsync-dst-plex-dst
ERROR can't connect to storage: cannot access storage path: stat /kopia: no such file or directory
```

---

## Solution

### Fix 1: Add Repository PVC Mount to ReplicationDestination

**File:** `kubernetes/components/volsync/replicationdestination.yaml`

**Current (Broken):**
```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: "${APP}-dst"
spec:
  trigger:
    manual: restore-once

  kopia:
    repository: "${APP}-volsync-secret"
    # MISSING: repositoryPVC configuration!

    destinationPVC: "${APP}-config"
    storageClassName: "${VOLSYNC_STORAGECLASS:=csi-cephfs-config-sc}"
    # ...
```

**Fixed:**
```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: "${APP}-dst"
spec:
  trigger:
    manual: restore-once

  kopia:
    repository: "${APP}-volsync-secret"
    repositoryPVC: "kopia"  # ← FIX: Mount kopia PVC at /repository

    destinationPVC: "${APP}-config"
    storageClassName: "${VOLSYNC_STORAGECLASS:=csi-cephfs-config-sc}"
    # ...
```

**What This Does:**
- Tells Volsync to mount the `kopia` PVC into the restore job pod
- Kopia repository becomes accessible at `/repository` (Volsync default mount path)
- Restore jobs can now read backup snapshots from the repository

### Fix 2: Increase Repository PVC Size

**File:** `kubernetes/components/volsync/kopia-repository-pvc.yaml`

**Current:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kopia
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: csi-cephfs-backups-sc
  resources:
    requests:
      storage: 1Gi  # Too small!
```

**Fixed:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kopia
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: csi-cephfs-backups-sc
  resources:
    requests:
      storage: 20Gi  # Increased for production use
```

**Capacity Planning:**
- Small apps (1-2Gi config): ~500MB compressed backup
- Medium apps (5-10Gi): ~2-5GB compressed
- Large apps (50Gi+ like Plex): ~10-15GB compressed
- With 24 hourly + 7 daily snapshots + deduplication
- **20Gi repository can handle 5-8 medium apps per namespace**

### Fix 3: Ensure Kopia Repository is Initialized

The repository must be initialized before first use. Check if initialization job exists:

**File:** Check if exists: `kubernetes/apps/6-data/kopia/app/kopia-init-job.yaml`

If missing, repository needs to be initialized manually per namespace:

```bash
# For each namespace using Volsync:
kubectl run -n default kopia-init --rm -it --restart=Never \
  --image=ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53 \
  --env="KOPIA_PASSWORD=$(kubectl get secret -n default kopia-secret -o jsonpath='{.data.KOPIA_PASSWORD}' | base64 -d)" \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "kopia",
      "image": "ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53",
      "stdin": true,
      "tty": true,
      "env": [{"name": "KOPIA_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "kopia-secret", "key": "KOPIA_PASSWORD"}}}],
      "command": ["/bin/sh", "-c", "kopia repository connect filesystem --path=/repository || kopia repository create filesystem --path=/repository"],
      "volumeMounts": [{"name": "repository", "mountPath": "/repository"}]
    }],
    "volumes": [{"name": "repository", "persistentVolumeClaim": {"claimName": "kopia"}}]
  }
}' -- /bin/sh
```

This connects to existing repository or creates it if missing.

---

## Implementation Steps

### Step 1: Update Component Templates

```bash
cd /Users/sulibot/repos/github/home-ops

# Edit replicationdestination.yaml - add repositoryPVC line
# Edit kopia-repository-pvc.yaml - change 1Gi to 20Gi

git add kubernetes/components/volsync/
git commit -m "fix(volsync): add repositoryPVC mount and increase repository size"
```

### Step 2: Apply Changes to Cluster

```bash
# Option A: Let Flux reconcile automatically (wait 10 minutes)
flux reconcile kustomization --with-source apps

# Option B: Force immediate reconcile
flux reconcile kustomization radarr -n flux-system --with-source
flux reconcile kustomization plex -n flux-system --with-source
```

### Step 3: Expand Existing Repository PVCs

For namespaces that already have 1Gi kopia PVCs:

```bash
# Check current size
kubectl get pvc kopia -n default

# Edit PVC to increase size
kubectl patch pvc kopia -n default -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# Verify expansion
kubectl get pvc kopia -n default -w
# Wait for status to show 20Gi
```

Ceph RBD/CephFS supports online expansion, so PVCs will grow automatically.

### Step 4: Initialize Kopia Repositories

For each namespace using Volsync (default, observability, etc.):

```bash
# Check if repository already initialized
kubectl exec -n default -it deployment/kopia -- kopia repository status --config-file=/config/repository.config

# If not initialized, run init command (see Fix 3 above)
```

### Step 5: Test Restore on Single App

Test with radarr (already has some data, low risk):

```bash
# Delete existing PVC to trigger restore
kubectl delete pvc radarr-config -n default

# Trigger restore
kubectl patch replicationdestination radarr-dst -n default \
  --type merge \
  --patch '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'

# Watch restore job
kubectl get jobs -n default -l app.kubernetes.io/created-by=volsync -w

# Check logs
kubectl logs -n default -l volsync.backube/replication-destination=radarr-dst --tail=50 -f

# Verify PVC created and data restored
kubectl exec -n default deploy/radarr -- ls -la /config/
# Should show radarr.db, config.xml, etc.
```

### Step 6: Roll Out to Other Apps

Once radarr restore succeeds, repeat for other apps:

**Low risk (test first):**
- mosquitto
- redis
- notifier

**Medium risk:**
- sonarr, prowlarr, lidarr
- home-assistant
- tautulli

**High value (test last):**
- plex (50Gi metadata)
- immich (media library)

For each app:
1. Delete PVC: `kubectl delete pvc ${APP}-config -n default`
2. Trigger restore: `kubectl patch replicationdestination ${APP}-dst -n default --type merge --patch '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'`
3. Verify restore: `kubectl logs -n default -l volsync.backube/replication-destination=${APP}-dst --tail=100`
4. Check data: `kubectl exec -n default deploy/${APP} -- ls -la /config/`

---

## Verification

### Check Repository Access

After fixes applied, verify restore jobs can access repository:

```bash
# Trigger test restore
kubectl patch replicationdestination radarr-dst -n default \
  --type merge \
  --patch '{"spec":{"trigger":{"manual":"restore-test"}}}'

# Check job logs - should NOT see /kopia errors
kubectl logs -n default -l volsync.backube/replication-destination=radarr-dst --tail=50

# Expected SUCCESS output:
# Connecting to repository filesystem:///repository
# Repository connected successfully
# Finding latest snapshot...
# Restoring snapshot to /data...
# Restore complete
```

### Check Backup Status

Verify backups are still working:

```bash
# List all ReplicationSources
kubectl get replicationsource -A

# Check recent backup
kubectl describe replicationsource radarr-src -n default

# Should show:
#   Last Sync Time: <recent timestamp>
#   Last Sync Duration: ~1-2 minutes
#   Next Sync Time: <next hour>
```

### Check Repository Contents

Connect to Kopia repository and list snapshots:

```bash
kubectl run -n default kopia-cli --rm -it --restart=Never \
  --image=ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53 \
  --env="KOPIA_PASSWORD=$(kubectl get secret -n default kopia-secret -o jsonpath='{.data.KOPIA_PASSWORD}' | base64 -d)" \
  --overrides='
{
  "spec": {
    "containers": [{
      "name": "kopia",
      "image": "ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53",
      "stdin": true,
      "tty": true,
      "env": [{"name": "KOPIA_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "kopia-secret", "key": "KOPIA_PASSWORD"}}}],
      "volumeMounts": [{"name": "repository", "mountPath": "/repository"}]
    }],
    "volumes": [{"name": "repository", "persistentVolumeClaim": {"claimName": "kopia"}}]
  }
}' -- /bin/sh

# Inside the pod:
kopia repository connect filesystem --path=/repository
kopia snapshot list
kopia snapshot list --all
kopia repository status
```

Expected output should show snapshots for each app with hourly backups.

---

## Troubleshooting

### Issue: Restore Job Still Fails with "/kopia not found"

**Check:**
```bash
kubectl get replicationdestination radarr-dst -n default -o yaml | grep repositoryPVC
```

Should show: `repositoryPVC: kopia`

If missing, component change didn't apply. Force reconcile:
```bash
flux reconcile kustomization radarr -n flux-system --with-source
```

### Issue: Repository "Not Found" or "Invalid"

Repository needs initialization:
```bash
# Run kopia init command from Fix 3 above
```

### Issue: PVC Expansion Stuck

Check PVC events:
```bash
kubectl describe pvc kopia -n default
```

If stuck, the storage class might not support expansion. Verify:
```bash
kubectl get storageclass csi-cephfs-backups-sc -o yaml | grep allowVolumeExpansion
# Should show: allowVolumeExpansion: true
```

### Issue: Restore Creates PVC but Data is Empty

Repository might be empty (no backups yet). Check:
```bash
kopia snapshot list  # From kopia-cli pod above
```

If empty, backups haven't run yet. Wait for next hourly backup or trigger manually:
```bash
kubectl patch replicationsource radarr-src -n default \
  --type merge \
  --patch '{"spec":{"trigger":{"manual":"backup-'$(date +%s)'"}}}'
```

---

## Success Criteria

- ✅ Restore jobs complete without "/kopia" errors
- ✅ Restore jobs show "Repository connected" in logs
- ✅ PVCs created with actual restored data (not empty)
- ✅ Applications start with previous configuration
- ✅ Kopia repository accessible from CLI
- ✅ Snapshots visible in repository
- ✅ Backups continue to run hourly

---

## Post-Fix Monitoring

### Add Prometheus Alerts

Ensure alerts exist for:
- Backup failures (`VolsyncBackupFailed`)
- Restore failures (`VolsyncRestoreFailed`)
- Repository errors (`KopiaRepositoryError`)

Check: `kubernetes/apps/6-data/volsync/app/prometheusrule.yaml`

### Check Grafana Dashboard

View backup status: `kubernetes/apps/6-data/volsync/app/grafanadashboard.yaml`

Dashboard should show:
- Last successful backup timestamp per app
- Backup duration trends
- Restore success/failure counts
- Repository size usage

### Regular Maintenance

**Weekly:**
- Review backup success rate: `kubectl get replicationsource -A`
- Check repository size: `kubectl exec -n default deploy/kopia -- df -h /repository`

**Monthly:**
- Test restore procedure on one app
- Verify snapshots exist: `kopia snapshot list --all`
- Check retention policy working (24 hourly + 7 daily)

---

## Files Modified

1. `kubernetes/components/volsync/replicationdestination.yaml` - Add `repositoryPVC: "kopia"`
2. `kubernetes/components/volsync/kopia-repository-pvc.yaml` - Increase storage to 20Gi

## Timeline

- **Changes:** 10 minutes
- **Testing (single app):** 30 minutes
- **Rollout (all apps):** 1-2 hours (depending on app count)
- **Total:** ~2-3 hours

---

## Next Steps After This Fix

Future improvements (lower priority):

1. **Automate Repository Initialization** - Create Job in volsync component
2. **Centralized Repository** - Single cluster-wide repository instead of per-namespace (better deduplication)
3. **Off-site Replication** - Add S3 backend for off-cluster backups
4. **Restore Testing** - Monthly automated restore validation
5. **SOPS Bootstrap Automation** - Sealed Secrets integration (discussed earlier, deferred)

---

## Post-Rebuild Manual Trigger Restoration (Option 2)

When rebuilding the cluster, use manual triggers to control restore order and avoid resource contention.

### How It Works

The VolSync component uses `trigger: manual: restore-once`. After cluster rebuild:
- All ReplicationDestinations are created but **NOT started**
- To start a restore, change the manual trigger value
- Restores process sequentially (VolSync queues them automatically)
- You control which apps restore first

### Batch Restoration Script

Save as `restore-volsync-batches.sh`:

```bash
#!/bin/bash
# VolSync Manual Trigger Batch Restore
# Triggers restores in priority order to avoid overwhelming the cluster

set -e

# Batch definitions
BATCH_1=(mosquitto redis tautulli)
BATCH_2=(prowlarr qui thelounge)
BATCH_3=(nzbget sabnzbd qbittorrent)
BATCH_4=(sonarr sonarr-4k radarr radarr-4k lidarr)
BATCH_5=(emby immich)
BATCH_6=(atuin autobrr bookshelf filebrowser home-assistant seerr slskd)

trigger_restore() {
    local app=$1
    local ts=$(date +%s)
    echo "Triggering: $app"
    kubectl patch replicationdestination ${app}-dst -n default \
        --type merge -p "{\"spec\":{\"trigger\":{\"manual\":\"restore-${ts}\"}}}"
}

wait_for_batch() {
    echo "Waiting for batch to complete..."
    while true; do
        pending=$(kubectl get replicationdestination -n default -o json | \
            jq '[.items[] | select(.status.lastSyncTime == null)] | length')
        if [ "$pending" -eq 0 ]; then
            echo "Batch complete!"
            break
        fi
        echo "  $pending restores pending..."
        sleep 30
    done
}

# Execute batches
for batch in "BATCH_1[@]" "BATCH_2[@]" "BATCH_3[@]" "BATCH_4[@]" "BATCH_5[@]" "BATCH_6[@]"; do
    for app in "${!batch}"; do
        trigger_restore "$app"
    done
    wait_for_batch
done
```

### Manual Commands (Individual Apps)

**Batch 1 - Quick Start:**
```bash
kubectl patch replicationdestination mosquitto-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination redis-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination tautulli-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

**Batch 2 - Media Utilities:**
```bash
kubectl patch replicationdestination prowlarr-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination qui-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination thelounge-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

**Batch 3 - Download Clients:**
```bash
kubectl patch replicationdestination nzbget-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination sabnzbd-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination qbittorrent-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

**Batch 4 - *arr Apps:**
```bash
kubectl patch replicationdestination sonarr-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination sonarr-4k-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination radarr-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination radarr-4k-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination lidarr-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

**Batch 5 - Media Servers:**
```bash
kubectl patch replicationdestination emby-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination immich-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

**Batch 6 - Remaining:**
```bash
kubectl patch replicationdestination atuin-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination autobrr-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination bookshelf-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination filebrowser-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination home-assistant-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination seerr-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
kubectl patch replicationdestination slskd-dst -n default --type merge -p '{"spec":{"trigger":{"manual":"restore-'$(date +%s)'"}}}'
```

### Monitoring Restores

```bash
# Check all ReplicationDestinations
kubectl get replicationdestination -n default

# Watch restore pods
kubectl get pods -n default | grep volsync-dst

# Monitor specific restore
kubectl logs -f -n default -l volsync.backube/replication-destination=<app>-dst

# Check completion status
kubectl get replicationdestination -n default -o custom-columns=\
NAME:.metadata.name,LAST_SYNC:.status.lastSyncTime,DURATION:.status.lastSyncDuration
```

### Post-Rebuild Checklist

- [ ] Cluster rebuilt, Flux deployed
- [ ] Kopia repository PVC created and bound
- [ ] VolSync controller running
- [ ] CephFS CSI healthy
- [ ] Run batch script or trigger manually
- [ ] Monitor each batch completion
- [ ] **Plex:** Restore manually (volsync disabled)

### Current Plex Status

- **VolSync:** DISABLED in ks.yaml
- **GPU:** DISABLED in helmrelease.yaml
- **PVC:** Simple 50Gi (no auto-restore)
- **Action:** Manual restore after cluster rebuild

## Questions?

Before implementing, confirm:

1. **Repository Size:** Is 20Gi per namespace reasonable for your app count/sizes?
2. **Testing Strategy:** Test on radarr first, then roll out to other apps?
3. **Timing:** Apply changes now or during scheduled maintenance window?
4. **Post-Rebuild:** Use batch script for controlled restoration?

Ready to proceed with implementation?
