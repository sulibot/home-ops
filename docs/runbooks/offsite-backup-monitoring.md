# Offsite backup monitoring and response

## Purpose

This runbook covers the Backblaze B2 operational repositories and the Google
Cloud Archive content tier. The operating model is:

1. prove that credentials and schedules exist;
2. detect failed or long-running executions;
3. measure age since the last successful copy against the intended RPO;
4. prove recoverability with bounded, recurring restore drills;
5. review remote capacity and cost without paging on normal growth.

Backup completion alone is not proof of recovery. A tier is considered healthy
only when both its copy and its corresponding restore drill are within their
freshness windows.

## Approved-data gate

The data owner approved this allowlist on 2026-07-29. Schedules remain
suspended only until their one-time bootstrap and real restore gates pass.

| Destination | Source | Included data |
|---|---|---|
| GCS Archive | `/content/library` | Immich originals |
| GCS Archive | `/content/upload` | Immich upload staging |
| GCS Archive | `/content/profile` | Immich user profile images |
| GCS Archive | `/content/backups` | Immich application-managed database dumps |
| GCS Archive | `/content/users` | All current and future user storage |
| GCS Archive | `/content/data/media/music` | Music |
| GCS Archive | `/content/data/media/audiobooks` | Audiobooks |
| GCS Archive | `/content/data/media/books` | Books |
| B2 Kopia | Existing MinIO Kopia repository | Kubernetes application PVC snapshots |
| B2 CNPG | `cnpg-backups/postgres-vectorchord` | PostgreSQL base backups and WAL |
| B2 immutable infrastructure | `terraform-state/live` | Live Terraform state history |
| B2 immutable infrastructure | OpenBao active Raft leader | Application-consistent Raft snapshots |

The GCS job is allowlist-only. It does not traverse movies, `movies-4k`, TV,
`tv-4k`, sports, `vids`, download staging, or Immich derivatives such as
thumbnails and encoded video. PBS is a later phase.

## Service objectives

| Signal | Schedule | Warning threshold | Operator outcome |
|---|---:|---:|---|
| Kopia repository copy to B2 | 6 hours | 14 hours without success | Restore the copy path inside the same day |
| CNPG/Terraform copy and OpenBao freshness gate | 6 hours | 14 hours without success | Restore the copy path inside the same day |
| GCS content archive | Weekly | 9 days without success | Repair before a second weekly run is missed |
| B2 Kopia restore drill | Weekly | 14 days without success | Re-establish tested PVC recovery |
| GCS content restore drill | Monthly | 45 days without success | Re-establish tested decryption and Archive reads |
| CNPG restore drill | Monthly | 45 days without success | Re-establish tested database recovery and SQL validation |

The first successful full drills establish measured RTOs. Record duration,
restored bytes/files, database, and verification result; do not advertise an
unmeasured RTO.

Initial measured baseline:

| Date | Drill | Result | Measured recovery duration |
|---|---|---|---:|
| 2026-07-29 | CNPG/Barman from B2 | Latest base backup, WAL replay, primary promotion, SQL check, cleanup | 242 seconds |

## Implemented monitoring

The `SRE Offsite Backup` Grafana dashboard reports:

- expected CronJobs present and schedules enabled;
- enabled schedules that have never succeeded;
- age of each last successful run;
- active and failed Jobs;
- firing backup alerts;
- correlated Kubernetes Job logs.

Prometheus alerts cover:

- fewer than six expected CronJobs;
- any of the three offsite ExternalSecrets not Ready;
- Job failure within the last hour;
- non-archive Jobs active for more than three hours;
- GCS archive active for more than thirty hours;
- copy or restore freshness outside its service objective;
- schedules that are enabled but have never succeeded.

Warnings create or update a Linear issue and send a Pushover notification
outside quiet hours through the existing Alertmanager routes.

Remote stored bytes and provider invoices are provider-authoritative:

- GCP budget notifications fire at 50%, 90%, 100%, and forecast thresholds;
- review GCS and B2 stored bytes/object counts monthly and after bootstraps;
- investigate unplanned month-over-month growth above 20%;
- do not routinely restore the full media archive solely as a monitoring test,
  because Archive retrieval and network egress are chargeable.

## Triage

### 1. Confirm the control plane

```bash
kubectl get cronjob -n volsync-system \
  volsync-offsite-kopia-sync \
  minio-selected-offsite-copy \
  gcs-content-archive \
  gcs-content-restore-drill \
  volsync-offsite-restore-drill

kubectl get cronjob -n backup-restore-drill cnpg-offsite-restore-drill

kubectl get externalsecret -n volsync-system volsync-offsite-s3
kubectl get externalsecret -n volsync-system gcs-content-archive
kubectl get externalsecret -n backup-restore-drill cnpg-offsite-restore-s3
```

Before activation, `SUSPEND=True` is expected. After the bootstrap and data
approval gate, Git must declare all six schedules unsuspended.

### 2. Inspect the most recent Job

```bash
kubectl get jobs -A --sort-by=.metadata.creationTimestamp |
  grep -E 'offsite|gcs-content|minio-selected'

kubectl logs -n <namespace> job/<job-name> --tail=300
kubectl describe job -n <namespace> <job-name>
```

Do not delete the failed Job until its logs and Kubernetes events have been
captured. Job history and Loki are the primary execution evidence.

### 3. Classify the failure

| Symptom | Likely layer | First check |
|---|---|---|
| ExternalSecret not Ready | 1Password contract or operator | Missing item field and ExternalSecret events |
| 401/403 from B2 or GCS | Credential scope or rotation | Bucket-scoped key and endpoint |
| Source path missing | CephFS mount/layout drift | Read-only `offsite-content-source` PVC and path |
| Timeout or long-running copy | Network, provider, or source churn | Job transfer statistics and bandwidth cap |
| Kopia restore failure | Repository sync, password, or snapshot identity | Kopia target connection and snapshot list |
| CNPG recovery failure | Barman object layout/WAL continuity | ObjectStore status and CNPG pod events |
| GCS decrypt failure | Crypt password/salt mismatch | Owner-controlled offline recovery material |
| OpenBao freshness failure | Leader timer, snapshot AppRole, or B2 upload | `openbao-backup.timer` and `openbao-backup.service` on all three members |

### 4. Recover safely

1. Keep a failing schedule suspended if retries would create cost or overwrite
   useful evidence.
2. Repair credentials or connectivity with the smallest bucket-scoped
   permission set.
3. Create one manual Job from the CronJob and watch it to completion.
4. Run the matching bounded restore drill.
5. Confirm the Prometheus last-success timestamp advances.
6. Re-enable the schedule in Git and close the incident only after the restore
   proof passes.

Never test a change by deleting the only known-good remote objects.

## Monthly management review

Record:

- last success age for all six schedules;
- failed and long-running Job count;
- measured drill RTO and restored bytes/files;
- GCS and B2 stored bytes, object count, and invoice;
- unexpected growth, lifecycle deletions, or key rotations;
- any alert that fired without an actionable operator response.

Tune thresholds only after reviewing at least two normal execution cycles.
