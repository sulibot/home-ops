# Backup System Documentation

## Overview

This Kubernetes cluster uses **Volsync + Kopia** for automated backup and disaster recovery of application configuration data. The system provides hourly backups with automated verification, monitoring, and cross-namespace support.

## Architecture

### Components

1. **Kopia** - Deduplicating backup engine with encryption and compression
2. **Volsync** - Kubernetes operator that orchestrates backup/restore operations
3. **CephFS** - Shared storage backend for the centralized backup repository
4. **Flux** - GitOps controller managing the backup infrastructure

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Namespaces                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ App PVC  │  │ App PVC  │  │ App PVC  │  │ App PVC  │       │
│  │ (config) │  │ (config) │  │ (config) │  │ (config) │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
│       │             │             │             │               │
│       ▼             ▼             ▼             ▼               │
│  ┌────────────────────────────────────────────────────┐        │
│  │         Volsync ReplicationSource (hourly)         │        │
│  │   - Creates snapshots                              │        │
│  │   - Runs Kopia backup jobs                         │        │
│  │   - Manages retention (24h/7d)                     │        │
│  └────────────────────┬───────────────────────────────┘        │
└───────────────────────┼────────────────────────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────┐
         │  Kopia Repository (CephFS)   │
         │  - Encrypted & deduplicated  │
         │  - Shared across namespaces  │
         │  - 200Gi RWX PVC             │
         └──────────────────────────────┘
                        │
                        ▼
         ┌──────────────────────────────┐
         │    Kopia Web UI (optional)   │
         │  https://kopia.sulibot.com   │
         │  - Browse snapshots          │
         │  - View repository stats     │
         └──────────────────────────────┘
```

### Storage Architecture

All namespaces share a **single centralized Kopia repository** stored on CephFS:

```
CephFS Subvolume (RWX, 200Gi)
├─ volumeHandle: 0001-0024-407036f5-...-84e672d78c4e
│
├─ PV: kopia-repository-pv-volsync-system
│  └─ PVC: kopia (volsync-system namespace)
│
├─ PV: kopia-repository-pv-default
│  └─ PVC: kopia (default namespace)
│
└─ PV: kopia-repository-pv-observability
   └─ PVC: kopia (observability namespace)
```

**Key Points:**
- All PVs reference the **same CephFS volumeHandle**
- Multiple PVCs can mount the same RWX volume
- Repository path: `/repository/repository` (mount point + subdirectory)

## How Backups Work

### Backup Process (Automated - Hourly)

1. **Trigger**: Volsync schedules backup at `:00` of every hour (`0 * * * *`)
2. **Snapshot**: VolumeSnapshot created from source PVC
3. **Mover Job**: Kubernetes Job spawned with Kopia sidecar
4. **Backup**: Kopia connects to repository and backs up snapshot data
5. **Retention**: Old snapshots pruned according to policy (24 hourly, 7 daily)
6. **Cleanup**: Snapshot and job cleaned up after success

### What Gets Backed Up

**Currently Enabled:**
- ✅ Application configuration PVCs in `default` namespace (atuin, autobrr, bookshelf, emby, etc.)
- ✅ Grafana dashboards/config in `observability` namespace
- ✅ Gatus status page config in `observability` namespace

**Explicitly Excluded:**
- ❌ Prometheus metrics (time-series data - regenerates)
- ❌ Victoria Logs data (log data - ephemeral)
- ❌ Media files (movies, TV shows - too large)
- ❌ Download caches (temporary data)

### Retention Policy

```yaml
retain:
  hourly: 24    # Keep 24 hourly snapshots (1 day)
  daily: 7      # Keep 7 daily snapshots (1 week)
```

**Storage Impact:**
- With deduplication, typical retention uses ~5-10GB per app
- First backup is full, subsequent backups are incremental
- Compression: zstd-fastest

## Disaster Recovery

### Scenario 1: Single App Recovery (Mild)

**Use Case:** Accidentally deleted config, corrupted database

**Recovery Steps:**

1. **Identify the snapshot:**
   ```bash
   kubectl get replicationsource -n <namespace> <app>-src -o yaml
   # Note the latest snapshot time
   ```

2. **Create ReplicationDestination:**
   ```bash
   cd kubernetes/apps/<tier>/<namespace>/<app>/

   # Create restore file
   cat > restore.yaml <<EOF
   apiVersion: volsync.backube/v1alpha1
   kind: ReplicationDestination
   metadata:
     name: ${APP}-restore
   spec:
     trigger:
       manual: restore-once
     kopia:
       repository: ${APP}-volsync-secret
       repositoryPVC: kopia
       accessModes:
         - ReadWriteMany
       capacity: 5Gi
       storageClassName: csi-cephfs-config-sc
       destinationPVC: ${APP}-config-restored
   EOF

   kubectl apply -f restore.yaml
   ```

3. **Wait for restore:**
   ```bash
   kubectl wait --for=condition=complete \
     replicationdestination/${APP}-restore \
     -n <namespace> --timeout=5m
   ```

4. **Replace PVC:**
   ```bash
   # Scale down app
   kubectl scale deployment <app> --replicas=0 -n <namespace>

   # Swap PVCs (backup original, use restored)
   kubectl delete pvc ${APP}-config -n <namespace>
   kubectl patch pvc ${APP}-config-restored \
     --type=merge -p '{"metadata":{"name":"'${APP}'-config"}}'

   # Scale up app
   kubectl scale deployment <app> --replicas=1 -n <namespace>
   ```

### Scenario 2: Namespace Recovery (Moderate)

**Use Case:** Entire namespace deleted, multiple apps need recovery

**Recovery Steps:**

1. **Ensure namespace exists:**
   ```bash
   kubectl create namespace <namespace>
   ```

2. **Ensure Kopia repository PVC exists:**
   ```bash
   # Check if PVC exists
   kubectl get pvc -n <namespace> kopia

   # If not, create it following the cross-namespace guide:
   # kubernetes/components/volsync/README-cross-namespace.md
   ```

3. **Deploy ReplicationDestination for each app:**
   ```bash
   for app in app1 app2 app3; do
     kubectl apply -f - <<EOF
   apiVersion: volsync.backube/v1alpha1
   kind: ReplicationDestination
   metadata:
     name: ${app}-dst
     namespace: <namespace>
   spec:
     trigger:
       manual: restore-once
     kopia:
       repository: ${app}-volsync-secret
       repositoryPVC: kopia
       accessModes: [ReadWriteMany]
       capacity: 5Gi
       storageClassName: csi-cephfs-config-sc
       destinationPVC: ${app}-config
   EOF
   done
   ```

4. **Monitor restores:**
   ```bash
   watch kubectl get replicationdestination -n <namespace>
   ```

5. **Redeploy applications via Flux:**
   ```bash
   flux reconcile kustomization <app> --with-source
   ```

### Scenario 3: Complete Cluster Rebuild (Severe)

**Use Case:** Total cluster failure, rebuilding from scratch

**Recovery Steps:**

1. **Bootstrap new cluster:**
   ```bash
   # Bootstrap Flux
   flux bootstrap github \
     --owner=sulibot \
     --repository=home-ops \
     --path=kubernetes/flux
   ```

2. **Wait for Volsync to deploy:**
   ```bash
   kubectl wait --for=condition=ready pod \
     -l app.kubernetes.io/name=volsync \
     -n volsync-system --timeout=5m
   ```

3. **Restore Kopia repository access:**
   The Kopia repository on CephFS persists! It will be automatically mounted when the cluster recreates PVCs.

4. **ReplicationDestinations auto-restore:**
   All apps configured with Volsync include a `ReplicationDestination` with `trigger.manual: restore-once`. These will **automatically restore** on cluster rebuild!

   ```yaml
   # This is already configured in each app via Flux
   spec:
     trigger:
       manual: restore-once  # Runs once on creation
   ```

5. **Monitor mass restore:**
   ```bash
   # Check all restores across namespaces
   kubectl get replicationdestination -A

   # Watch progress
   watch -n 5 'kubectl get replicationdestination -A | grep -E "restore-once|Synchronizing"'
   ```

6. **Verify applications:**
   ```bash
   # Check pod status
   kubectl get pods -A

   # Verify data restored
   kubectl exec -n default deployment/atuin -- ls -la /config
   ```

## Monitoring & Alerts

### Built-in Monitoring

**PrometheusRule Alerts** (`volsync-alerts`):

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| `VolsyncRestoreStuck` | Restore > 1 hour | Warning | Check mover job logs, consider manual intervention |
| `VolsyncBackupFailed` | Backup job failed | Warning | Review mover job logs, verify Kopia connectivity |
| `VolsyncBackupStale` | No backup in 25h | Warning | Check if app is running, verify ReplicationSource |
| `KopiaServerDown` | Kopia UI unreachable | Critical | Restart kopia pod, check repository connectivity |
| `VolsyncMoverJobFailed` | Mover job exit code > 0 | Warning | Check job logs for errors |

**Automated Detection:**

- **Stuck Restore Detector**: CronJob runs every 15 minutes to detect stuck restores
  - Location: `volsync-stuck-restore-detector` in `volsync-system`
  - Threshold: 60 minutes
  - Action: Logs warning (auto-fix disabled by default)

- **Backup Verifier**: CronJob runs daily at 6 AM
  - Location: `volsync-backup-verifier` in `volsync-system`
  - Validates: Snapshot integrity using Kopia's built-in verification
  - Reports: Total snapshots, daily counts, per-source metrics

### Manual Verification

**Check backup status:**
```bash
# List all ReplicationSources
kubectl get replicationsource -A

# Check specific app backup status
kubectl describe replicationsource -n <namespace> <app>-src

# View mover job logs
kubectl logs -n <namespace> -l volsync.backube/replication-source=<app>-src
```

**Access Kopia UI:**
```bash
# Port-forward to Kopia server
kubectl port-forward -n volsync-system svc/kopia 8080:80

# Open browser: http://localhost:8080
# Browse snapshots, check repository health
```

**Manual backup verification:**
```bash
# Run verification job
kubectl create job --from=cronjob/volsync-backup-verifier \
  verify-now -n volsync-system

# Watch logs
kubectl logs -n volsync-system job/verify-now -f
```

## Common Tasks

### Enable Backups for New App

1. **Add Volsync component to app Kustomization:**

   Edit `kubernetes/apps/<tier>/<namespace>/<app>/ks.yaml`:
   ```yaml
   spec:
     components:
       - ../../../../components/volsync
     dependsOn:
       - name: volsync
         namespace: flux-system
       - name: ceph-csi
         namespace: flux-system
     postBuild:
       substitute:
         APP: myapp
         VOLSYNC_CAPACITY: 5Gi
         VOLSYNC_STORAGECLASS: csi-cephfs-config-sc
         VOLSYNC_SNAPSHOTCLASS: csi-cephfs-config-snapclass
   ```

2. **If PVC name doesn't follow `${APP}-config` pattern:**
   ```yaml
   postBuild:
     substitute:
       APP: myapp
       VOLSYNC_SOURCE_PVC: custom-pvc-name  # Override default
   ```

3. **Commit and let Flux apply:**
   ```bash
   git add kubernetes/apps/<tier>/<namespace>/<app>/ks.yaml
   git commit -m "feat: Enable Volsync backups for myapp"
   git push

   flux reconcile kustomization <app>
   ```

4. **Verify backup created:**
   ```bash
   # Wait for next hour
   kubectl get replicationsource -n <namespace> myapp-src

   # Should show "lastSyncTime" within past hour
   ```

### Enable Backups in New Namespace

Follow the guide: [kubernetes/components/volsync/README-cross-namespace.md](../kubernetes/components/volsync/README-cross-namespace.md)

**Summary:**
1. Get volumeHandle from existing Kopia PV
2. Create static PV referencing same volumeHandle
3. Create PVC binding to the PV
4. Deploy via Flux
5. Apps in that namespace can now use Volsync

### Change Backup Schedule

**Default:** Hourly at `:00` (`0 * * * *`)

**To modify:**

Edit `kubernetes/components/volsync/replicationsource.yaml`:
```yaml
spec:
  trigger:
    schedule: "0 */6 * * *"  # Every 6 hours
    # OR
    schedule: "0 2 * * *"    # Daily at 2 AM
```

Commit and push. Flux will update all ReplicationSources.

### Manually Trigger Backup

```bash
# Delete the ReplicationSource (don't worry, it's declarative)
kubectl delete replicationsource -n <namespace> <app>-src

# Flux will recreate it within 15 minutes, triggering a backup
flux reconcile kustomization <app>

# Or force immediate reconcile
kubectl apply -f kubernetes/components/volsync/replicationsource.yaml
```

### Troubleshooting Stuck Backup

**Symptoms:** `lastSyncTime` not updating, mover job running for hours

**Diagnosis:**
```bash
# 1. Check ReplicationSource status
kubectl describe replicationsource -n <namespace> <app>-src

# 2. Check mover job
kubectl get jobs -n <namespace> -l volsync.backube/replication-source=<app>-src

# 3. Check mover job logs
kubectl logs -n <namespace> job/<mover-job-name>

# 4. Check Kopia repository connectivity
kubectl exec -n volsync-system deployment/kopia -- \
  kopia repository status --config-file=/config/repository.config
```

**Common Issues:**

| Issue | Cause | Solution |
|-------|-------|----------|
| `BLOB not found` | Repository path mismatch | Verify `/repository/repository` path |
| `password incorrect` | Credential mismatch | Check `kopia-secret` in 1Password |
| `No such file or directory` | Source PVC doesn't exist | Verify PVC name in `VOLSYNC_SOURCE_PVC` |
| `snapshot creation failed` | Snapshot class missing | Check `VOLSYNC_SNAPSHOTCLASS` |
| `connection timeout` | Kopia server down | Restart kopia deployment |

**Fix:**
```bash
# Delete stuck job
kubectl delete jobs -n <namespace> -l volsync.backube/replication-source=<app>-src

# Volsync will retry on next schedule
```

## Security

### Encryption

**Repository Encryption:**
- Algorithm: AES256-GCM-HMAC-SHA256
- Password: Stored in 1Password, synced via External Secrets Operator
- Secret: `kopia-secret` in `volsync-system` namespace

**In Transit:**
- Kopia connects to repository over local filesystem (PVC mount)
- No network encryption needed for repository access
- Web UI uses HTTPS via Kubernetes Ingress/HTTPRoute

### Access Control

**RBAC:**
- Volsync operator: Cluster-wide permissions for ReplicationSource/Destination CRDs
- Mover jobs: Namespace-scoped ServiceAccount with PVC access
- Kopia server: Read/write access to repository PVC

**Credentials:**
- Repository password: External Secret from 1Password
- Kopia UI: No authentication (internal network only)

### Backup Integrity

**Verification:**
- Daily automated verification via `volsync-backup-verifier`
- Kopia's built-in integrity checks (BLAKE2B-256-128 hashing)
- Deduplication prevents data corruption propagation

## Performance

### Resource Usage

**Kopia Server:**
- CPU: 10m request, no limit
- Memory: 1Gi limit
- Storage: 200Gi PVC (CephFS)

**Mover Jobs (per backup):**
- CPU: Variable (not limited)
- Memory: ~256Mi average
- Duration: 30s - 5min depending on data size
- Parallelism: 2 concurrent operations

### Optimization

**Compression:**
- Algorithm: zstd-fastest (good compression, low CPU)
- Alternative: `zstd-better-compression` for slower but smaller backups

**Deduplication:**
- Block-level deduplication enabled by default
- Typical dedup ratio: 60-80% for config data

**Snapshot Performance:**
- CephFS snapshots are instant (CoW)
- No application downtime during backup

## Maintenance

### Regular Tasks

**Weekly:**
- [ ] Review PrometheusRule alerts in Grafana
- [ ] Check backup verification CronJob logs
- [ ] Verify backup counts haven't dropped unexpectedly

**Monthly:**
- [ ] Review repository size growth
- [ ] Test disaster recovery procedure (pick one app)
- [ ] Update Kopia/Volsync versions if available

**Quarterly:**
- [ ] Perform full cluster rebuild test in lab environment
- [ ] Review retention policy (adjust if needed)
- [ ] Audit which apps have backups enabled

### Kopia Repository Maintenance

**Automatic Maintenance:**
- Runs every 24 hours automatically
- Compacts old snapshots
- Removes unreferenced blobs
- Reports in Kopia pod logs

**Manual Maintenance:**
```bash
kubectl exec -n volsync-system deployment/kopia -- \
  kopia maintenance run --full --config-file=/config/repository.config
```

### Backup Rotation

Retention is automatic based on policy. To manually delete old snapshots:

```bash
# List snapshots
kubectl exec -n volsync-system deployment/kopia -- \
  kopia snapshot list --all --config-file=/config/repository.config

# Delete specific snapshot
kubectl exec -n volsync-system deployment/kopia -- \
  kopia snapshot delete <snapshot-id> --config-file=/config/repository.config
```

## References

- **Volsync Documentation**: https://volsync.readthedocs.io/
- **Kopia Documentation**: https://kopia.io/docs/
- **Cross-Namespace Setup**: [README-cross-namespace.md](../kubernetes/components/volsync/README-cross-namespace.md)
- **Detect Stuck Restores Script**: [detect-stuck-restores.sh](../kubernetes/apps/6-data/volsync/maintenance/detect-stuck-restores.sh)

## Support

**Getting Help:**
1. Check Prometheus alerts first
2. Review mover job logs
3. Inspect ReplicationSource/Destination status
4. Check Kopia repository health
5. If stuck, ask in #infrastructure Slack channel (include error logs)

**Emergency Contacts:**
- Primary: DevOps team (#devops-alerts)
- Secondary: Platform Engineering (@platform-eng)
- Escalation: On-call engineer (PagerDuty)
