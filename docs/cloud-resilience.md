# Cloud resilience and offsite backup

## Decision

Use separate hot and cold providers:

| Tier | Data | Provider | Why |
|---|---|---|---|
| Local primary | Workloads and content | Existing Ceph | Fast normal operation and recovery |
| Local backup | VolSync/Kopia and CNPG/Barman | Existing MinIO LXC | Fast repository and PITR recovery |
| Hot offsite | Kopia, CNPG, Terraform state, later PBS | Backblaze B2 | Mutable S3 repositories, no storage floor, inexpensive restore drills |
| Cold offsite | Personal originals | Google Cloud Archive in `us-central1` | Lowest idle cost, immediate reads, and simple recurring restore tests |
| Root of trust | OpenBao auto-unseal | GCP Cloud KMS | Independent key service already used by the stack |

B2 is the operational recovery target. Google Cloud Archive is disaster
insurance for content that cannot be downloaded or regenerated. Never place a
live Kopia, Barman, or PBS repository in the content archive.

## What is protected

The content archive uses an allowlist. It reads only:

- `/content/library` - Immich originals;
- `/content/upload` - Immich upload staging;
- `/content/profile` - Immich user profile images;
- `/content/backups` - Immich application-managed database dumps;
- `/content/users` - all user storage, including future data;
- `/content/data/media/music`;
- `/content/data/media/audiobooks`;
- `/content/data/media/books`.

It deliberately does not traverse:

- movies and `movies-4k`;
- TV and `tv-4k`;
- sports;
- `vids`;
- torrents, Usenet, Soulseek downloads, and other download staging;
- Immich thumbnails, encoded video, and other generated derivatives.

Current measured content is approximately 60 GB of Immich originals, 293 MB of
pending/legacy Immich uploads, 793 MB of Immich database dumps, 184 GB of
music, 2.2 GB of audiobooks, and a small books tree. Size the Immich library
for three times its current size, or about 181 GB. The resulting planned cold
set is approximately 368 GB plus future user storage.

The selected operational data is copied logically through provider APIs:

- the Kopia repository, approximately 40.6 GB, using `kopia repository
  sync-to s3`;
- `cnpg-backups/postgres-vectorchord`, approximately 17.8 GB, using
  `rclone copy`;
- authoritative Terraform state from `sulibot-terraform-state/live` in GCS,
  using a separate read-only identity and `rclone copy` to immutable B2.

Do not copy `/data` from the MinIO LXC. MinIO's filesystem is an implementation
detail and a raw copy can be inconsistent with the logical object repository.

## Expected cost

At the planned sizes:

- 58.4 GB of current operational repositories in B2 is approximately
  USD 0.41/month;
- adding an estimated 80 GB PBS working set would make B2 approximately
  USD 0.96/month before retained deltas;
- 368 GB in GCS Archive is approximately USD 0.44/month;
- user storage growth increases GCS Archive by approximately USD 0.0012 per GB
  per month.

GCS Archive retrieval costs USD 0.05/GiB and internet egress is normally USD
0.12/GiB at this scale. A complete 368 GiB cold recovery is therefore
approximately USD 62.56 plus request charges. Reads are immediate.

Archive has a rolling 365-day minimum storage duration per object. This is a
billing rule, not a locked retention policy or annual account contract. An
object can be deleted at any time, but deleting, replacing, or rewriting it
before day 365 bills the remaining storage duration. At this storage price,
deleting the entire planned 368 GB set immediately would cap the storage
commitment at approximately USD 5.30. Do not configure or lock a GCS bucket
retention policy.

## Kubernetes implementation

The offsite resources live in:

`kubernetes/apps/tier-1-infrastructure/volsync/maintenance`

Terraform state is authoritative in the regional Standard-class
`sulibot-terraform-state` GCS bucket, not in MinIO or the Archive-class content
bucket. The `gcs-terraform-state-offsite-copy` CronJob uses a separate
read-only GCS identity and an upload-only B2 identity; it never synchronizes
deletions. See `docs/runbooks/terraform-state-gcs.md`.

The existing B2 master-capability credential in 1Password is for account
administration only. Workloads use bucket-scoped keys.

| Resource | Schedule | Purpose |
|---|---|---|
| `volsync-offsite-kopia-sync` | Every 6 hours | Native Kopia repository synchronization to B2 |
| `minio-selected-offsite-copy` | Every 6 hours | CNPG copy plus OpenBao offsite freshness gate |
| `gcs-terraform-state-offsite-copy` | Every 6 hours | Authoritative GCS state copied to immutable B2 |
| `gcs-content-archive` | Weekly | Encrypted, append-only allowlisted content copy |
| `gcs-content-restore-drill` | Monthly | Decrypt and verify a bounded Archive-class probe |
| `volsync-offsite-restore-drill` | Weekly | Restore `actual-src@default:/data` from B2 |
| `cnpg-offsite-restore-drill` | Monthly | Recover CNPG from B2 and execute SQL |

The CNPG drill runs in `backup-restore-drill`, creates a disposable 60 GiB
cluster, restores the `immich` database, executes a SQL query, records the
duration in its logs, and removes the Cluster and PVC.

The first live B2 drill passed on 2026-07-29: it selected the latest base
backup, replayed the off-site WAL archive, promoted a healthy primary, returned
24 rows from the database-catalog check, and removed every disposable
resource. The measured recovery duration was 242 seconds. This is an initial
baseline, not an RTO commitment.

The first live Kopia drill also passed on 2026-07-29 after the complete
45.6 GB repository synchronization. It restored the latest
`actual-src@default:/data` snapshot from B2: four files totaling 113,533 bytes
in 119 seconds. This is an initial application-data recovery baseline, not an
RTO commitment.

Every OpenBao member runs the same six-hour systemd timer. The timer uses a
snapshot-only AppRole, but only the active Raft leader writes. It verifies the
snapshot archive checksums and uploads directly to
`sulibot-infrastructure-immutable/openbao/raft`. The B2 bucket applies 30-day
governance retention, and the monitored selected-copy job fails when no
OpenBao snapshot newer than eight hours exists.

The six ENG-340 provider CronJobs were activated on 2026-07-29 only after the
B2 Kopia, B2 CNPG, and GCS real-content restore gates passed. New provider jobs
must remain suspended until their least-privilege credentials, bootstrap copy,
monitoring, and restore test have all passed.

## Provider provisioning

### Backblaze B2

Create three private buckets:

1. `sulibot-kopia-offsite`
   - no Object Lock;
   - no default retention;
   - dedicated list/read/write/delete key;
   - Kopia client-side encryption remains authoritative.
2. `sulibot-cnpg-offsite`
   - versioning enabled;
   - dedicated list/read/write key;
   - automatically hide current objects after 30 days and delete hidden
     versions one day later;
   - do not allow the Kubernetes copier to bypass governance.
3. `sulibot-infrastructure-immutable`
   - versioning and Object Lock enabled;
   - 30-day default governance retention;
   - dedicated create/read/list key without delete or governance bypass;
   - stores Terraform state and future break-glass artifacts.

Keep the B2 account master key out of Kubernetes, PBS, and application
containers.

### Google Cloud Storage

Create a dedicated GCP project and one private Cloud Storage bucket:

1. project ID: `sulibot-personal-archive`;
2. bucket: `sulibot-personal-archive`, or a globally unique suffixed name if
   that name is unavailable;
3. location: regional `us-central1`;
4. default storage class: `ARCHIVE`;
5. enforce public access prevention and uniform bucket-level access;
6. enable Object Versioning and expire noncurrent versions only after they are
   at least 365 days old;
7. keep the default soft-delete policy initially;
8. do not create or lock a bucket retention policy;
9. create a dedicated service account with bucket-scoped Storage Object User
   access, but no bucket administration or retention-policy permissions;
10. set a small monthly billing budget and alerts;
11. use `ARCHIVE` for content/probes and `STANDARD` for small manifests.

Keep an owner-controlled recovery identity outside Kubernetes. The in-cluster
service account is allowed to update objects because user files can change;
Object Versioning and soft delete provide a recovery window for accidental
overwrites or deletion. Revisit stronger immutability only after the first
archive and restore drills have established normal behavior.

## 1Password contract

Create or update the `offsite-backup-s3` item with these fields:

| Field | Meaning |
|---|---|
| `s3-endpoint` | B2 S3 endpoint including `https://` |
| `region` | B2 bucket region |
| `kopia-bucket` | B2 Kopia bucket |
| `kopia-access-key-id` | bucket-scoped Kopia key ID |
| `kopia-application-key` | bucket-scoped Kopia application key |
| `minio-mirror-endpoint` | local MinIO endpoint including `https://` |
| `minio-mirror-access-key-id` | read-only key for selected source buckets |
| `minio-mirror-secret-access-key` | matching MinIO secret |
| `cnpg-bucket` | B2 CNPG bucket |
| `cnpg-access-key-id` | bucket-scoped CNPG key ID |
| `cnpg-application-key` | bucket-scoped CNPG application key |
| `infrastructure-bucket` | B2 immutable infrastructure bucket |
| `infrastructure-access-key-id` | bucket-scoped infrastructure key ID |
| `infrastructure-application-key` | matching B2 application key |
| `gcs-content-bucket` | Google Cloud Archive bucket |
| `gcs-service-account-json` | bucket-scoped GCS service-account JSON |
| `content-crypt-password` | high-entropy rclone crypt password |
| `content-crypt-salt` | independent high-entropy rclone crypt salt |

Keep independent offline copies of:

- the Kopia repository password;
- `content-crypt-password` and `content-crypt-salt`;
- B2 and GCS recovery credentials;
- SOPS identities, OpenBao recovery shares, and KMS recovery information.

The OpenBao nodes receive only the snapshot AppRole and the restricted
infrastructure-bucket key. Neither credential can read logical OpenBao secrets,
restore a Raft snapshot, delete B2 objects, or bypass governance retention.

Losing the rclone crypt password or salt makes the Google Cloud archive
unrecoverable.

## Bootstrap and activation

1. Provision the B2 buckets/keys and the GCS project, bucket, and service
   account.
2. Create the dedicated MinIO read-only service account. It needs list/get for:
   - `cnpg-backups/postgres-vectorchord/*`.
3. Populate the 1Password item and wait for all three ExternalSecrets to become
   Ready.
4. Run one manual Kopia synchronization and inspect its log.
5. Run one manual selected-MinIO copy and compare object counts/bytes.
6. Run the GCS content archive manually. Confirm Standard manifests and
   Archive content/probe objects are present.
7. Run the B2 Kopia restore drill.
8. Run the CNPG restore drill and confirm the SQL verification result.
9. Run the GCS content restore drill. It restores both the synthetic probe and
   one bounded real Immich original through the encrypted remote and verifies
   the original SHA-256 digest.
10. Change `suspend: true` to `suspend: false` for all six CronJobs.
11. Confirm Prometheus has recorded each CronJob's last successful timestamp.

Example manual bootstrap:

```bash
kubectl create job -n volsync-system \
  --from=cronjob/volsync-offsite-kopia-sync \
  volsync-offsite-kopia-bootstrap

kubectl create job -n volsync-system \
  --from=cronjob/minio-selected-offsite-copy \
  minio-selected-offsite-bootstrap

kubectl create job -n volsync-system \
  --from=cronjob/gcs-content-archive \
  gcs-content-bootstrap

kubectl create job -n volsync-system \
  --from=cronjob/gcs-content-restore-drill \
  gcs-content-restore-bootstrap
```

## Recovery order

1. Recover internet, DNS, an operator workstation, and 1Password access.
2. Use Git/SOPS and GCP KMS to recover cluster foundations and OpenBao.
3. Recover application configuration from the B2 Kopia repository.
4. Recover PostgreSQL from B2 CNPG/Barman objects and replay WAL.
5. Recover Terraform state and other immutable infrastructure artifacts.
6. Recreate PBS and attach its B2 S3 datastore when that phase is implemented.
7. Restore Google Cloud Archive content only if the local content filesystem is
   unavailable.

For GCS Archive, use the same service-account credential and rclone crypt
password/salt to copy objects directly to replacement storage. No thaw request
is required. Restore the probe and a small real content group first, verify
them, and then expand the copy. Use an owner-controlled recovery credential if
the in-cluster service account is unavailable or suspected compromised.

## Provider migration

The content layout and encryption are intentionally independent of GCS. To
migrate later:

1. provision the replacement object store and a second least-privilege remote;
2. configure a second rclone crypt remote with the same password and salt;
3. copy the decrypted namespace from `gcs-crypt:` to the replacement crypt
   remote;
4. compare the encrypted manifests, file counts, and total bytes;
5. pass a sample restore from the replacement provider;
6. switch the archive and drill jobs, but retain GCS until every object is at
   least 365 days old or explicitly accept the small early-deletion charge.

Migration reads are charged at GCS Archive retrieval and egress rates. Do not
delete the source archive until the target restore test passes.

## Monitoring and recovery objectives

- Kopia and selected-MinIO copies: target RPO 6 hours; alert after 14 hours.
- Content archive: target RPO 7 days; alert after 9 days.
- Content restore drill: monthly; alert after 45 days without success.
- Kopia drill: weekly; alert after 14 days without success.
- CNPG drill: monthly; alert after 45 days without success.
- Record restore duration, restored bytes/files, database name, and SQL result
  in Job logs.

The first successful drills establish the measured RTO. Do not claim an RTO
until those results exist.

The `SRE Offsite Backup` Grafana dashboard and the
[offsite backup monitoring runbook](runbooks/offsite-backup-monitoring.md)
implement the operating view. Alerts also cover missing CronJobs, credentials
that are not Ready, failed Jobs, long-running Jobs, and schedules that have
never succeeded. Provider consoles remain authoritative for stored bytes and
cost: GCP budget alerts are configured, and GCS/B2 capacity is reviewed
monthly rather than paging on normal archive growth.

## Provider comparison

| Provider | Decision |
|---|---|
| Backblaze B2 | Use for mutable operational repositories and drills |
| GCP Archive | Start here for encrypted personal originals; lowest idle cost and immediate restore testing |
| Scaleway Glacier | Migration option if full-recovery economics become more important than immediate reads |
| Scaleway One Zone | More expensive than B2 and only one zone; not selected |
| Scaleway Multi-AZ | Good service, but over twice B2's storage price |
| IDrive e2 | Revisit only if B2 remains above its cost crossover for two billing cycles |
| Cloudflare R2 | No S3 Object Lock and higher storage price |
| Wasabi | One-TB floor and 90-day minimum conflict with current size/pruning |

## Research sources

- [Backblaze B2 pricing](https://www.backblaze.com/cloud-storage/pricing)
- [Backblaze Object Lock](https://www.backblaze.com/docs/cloud-storage-object-lock)
- [Google Cloud Storage pricing](https://cloud.google.com/storage/pricing)
- [Google Cloud Storage classes](https://cloud.google.com/storage/docs/storage-classes)
- [Google Cloud Storage Bucket Lock](https://cloud.google.com/storage/docs/bucket-lock)
- [rclone Google Cloud Storage backend](https://rclone.org/googlecloudstorage/)
- [Scaleway Object Storage pricing](https://www.scaleway.com/en/pricing/storage/)
- [Scaleway Glacier restoration](https://www.scaleway.com/en/docs/object-storage/how-to/restore-an-object-from-glacier/)
- [Kopia repository synchronization](https://kopia.io/docs/advanced/synchronization/)
- [CNPG S3-compatible object stores](https://cloudnative-pg.io/docs/1.25/appendixes/object_stores/)
- [Proxmox PBS S3 datastores](https://pbs.proxmox.com/docs/storage.html#datastores-with-s3-backend)
- [Proxmox forum: B2 endpoint settings](https://forum.proxmox.com/threads/pbs-fails-to-connect-to-backblaze-b2.170220/)
- [Proxmox forum: do not raw-copy a live PBS datastore](https://forum.proxmox.com/threads/upload-backups-to-s3-compatible-cloud-storage.160250/)
