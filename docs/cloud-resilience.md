# Cloud resilience and offsite backup

## Decision

Use separate hot and cold providers:

| Tier | Data | Provider | Why |
|---|---|---|---|
| Local primary | Workloads and content | Existing Ceph | Fast normal operation and recovery |
| Local backup | VolSync/Kopia and CNPG/Barman | Existing MinIO LXC | Fast repository and PITR recovery |
| Hot offsite | Kopia, CNPG, Terraform state, later PBS | Backblaze B2 | Mutable S3 repositories, no storage floor, inexpensive restore drills |
| Cold offsite | Personal originals | Scaleway Glacier in `nl-ams` | Low-cost archive, Object Lock, inexpensive full-disaster retrieval |
| Root of trust | OpenBao auto-unseal | GCP Cloud KMS | Independent key service already used by the stack |

B2 is the operational recovery target. Scaleway Glacier is disaster insurance
for content that cannot be downloaded or regenerated. Never place a live
Kopia, Barman, or PBS repository in Glacier.

## What is protected

The content archive uses an allowlist. It reads only:

- `/content/library` - Immich originals;
- `/content/upload` - Immich upload staging;
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
- Immich thumbnails, encoded video, profile images, and other derivatives.

Current measured content is approximately 60 GB of Immich originals, 184 GB
of music, 2.2 GB of audiobooks, and a small books tree. Size the Immich library
for three times its current size, or about 181 GB. The resulting planned cold
set is approximately 367 GB plus future user storage.

The selected MinIO data is copied logically through S3:

- the Kopia repository, approximately 40.6 GB, using `kopia repository
  sync-to s3`;
- `cnpg-backups/postgres-vectorchord`, approximately 17.8 GB, using
  `rclone copy`;
- `terraform-state/live`, currently tiny but critical, using `rclone copy`.

Do not copy `/data` from the MinIO LXC. MinIO's filesystem is an implementation
detail and a raw copy can be inconsistent with the logical object repository.

## Expected cost

At the planned sizes:

- 58.4 GB of current operational repositories in B2 is approximately
  USD 0.41/month;
- adding an estimated 80 GB PBS working set would make B2 approximately
  USD 0.96/month before retained deltas;
- 367 GB in Scaleway Glacier is approximately EUR 0.93/month;
- user storage growth increases Glacier by approximately EUR 0.00254 per GB
  per month.

Scaleway Glacier restoration costs EUR 0.009/GB. The first 75 GB/month of
egress is free, then egress is EUR 0.01/GB. A complete 367 GB cold recovery is
therefore approximately EUR 6.22 plus short-lived Standard Multi-AZ storage.
The restore can take from a few minutes to 24 hours to start.

## Kubernetes implementation

The offsite resources live in:

`kubernetes/apps/tier-1-infrastructure/volsync/maintenance`

| Resource | Schedule | Purpose |
|---|---|---|
| `volsync-offsite-kopia-sync` | Every 6 hours | Native Kopia repository synchronization to B2 |
| `minio-selected-offsite-copy` | Every 6 hours | CNPG and Terraform state logical copy to B2 |
| `scaleway-content-archive` | Weekly | Encrypted, append-only allowlisted content copy |
| `volsync-offsite-restore-drill` | Weekly | Restore `actual-src@default:/data` from B2 |
| `cnpg-offsite-restore-drill` | Monthly | Recover CNPG from B2 and execute SQL |

The CNPG drill runs in `backup-restore-drill`, creates a disposable 60 GiB
cluster, restores the `immich` database, executes a SQL query, records the
duration in its logs, and removes the Cluster and PVC.

All new CronJobs are initially suspended. This prevents predictable alert
noise and failed Jobs before the provider buckets and least-privilege
credentials exist. Unsuspend them only after completing the provisioning and
bootstrap checklist below.

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
   - lifecycle old object versions after the agreed PITR window;
   - do not allow the Kubernetes copier to bypass governance.
3. `sulibot-infrastructure-immutable`
   - versioning and Object Lock enabled;
   - dedicated create/read/list key without delete or governance bypass;
   - stores Terraform state and future break-glass artifacts.

Keep the B2 account master key out of Kubernetes, PBS, and application
containers.

### Scaleway

Create one private Object Storage bucket in `nl-ams`:

1. enable versioning and Object Lock when the bucket is created;
2. start with 90-day governance retention;
3. block public access;
4. create a dedicated IAM application with object read/list/create access and
   no retention-administration permission;
5. set billing alerts for storage and egress;
6. use direct `GLACIER` uploads for content and `STANDARD` for small manifests.

Object Lock cannot be disabled after it is enabled. Keep governance mode until
at least one cold restore has passed; consider compliance mode only after the
retention and cost behavior is proven.

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
| `scaleway-endpoint` | for example `https://s3.nl-ams.scw.cloud` |
| `scaleway-region` | `nl-ams` |
| `scaleway-content-bucket` | Scaleway archive bucket |
| `scaleway-access-key-id` | least-privilege Scaleway access key |
| `scaleway-secret-access-key` | matching Scaleway secret |
| `content-crypt-password` | high-entropy rclone crypt password |
| `content-crypt-salt` | independent high-entropy rclone crypt salt |

Keep independent offline copies of:

- the Kopia repository password;
- `content-crypt-password` and `content-crypt-salt`;
- B2 and Scaleway recovery credentials;
- SOPS identities, OpenBao recovery shares, and KMS recovery information.

Losing the rclone crypt password or salt makes the Scaleway archive
unrecoverable.

## Bootstrap and activation

1. Provision the B2 and Scaleway buckets and keys.
2. Create the dedicated MinIO read-only service account. It needs list/get for:
   - `cnpg-backups/postgres-vectorchord/*`;
   - `terraform-state/live/*`.
3. Populate the 1Password item and wait for both ExternalSecrets to become
   Ready.
4. Run one manual Kopia synchronization and inspect its log.
5. Run one manual selected-MinIO copy and compare object counts/bytes.
6. Run the Scaleway content archive manually. Confirm Standard manifests and
   Glacier content objects are present.
7. Run the B2 Kopia restore drill.
8. Run the CNPG restore drill and confirm the SQL verification result.
9. Perform one manual Scaleway Glacier sample restore.
10. Change `suspend: true` to `suspend: false` for all five CronJobs.
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
  --from=cronjob/scaleway-content-archive \
  scaleway-content-bootstrap
```

## Recovery order

1. Recover internet, DNS, an operator workstation, and 1Password access.
2. Use Git/SOPS and GCP KMS to recover cluster foundations and OpenBao.
3. Recover application configuration from the B2 Kopia repository.
4. Recover PostgreSQL from B2 CNPG/Barman objects and replay WAL.
5. Recover Terraform state and other immutable infrastructure artifacts.
6. Recreate PBS and attach its B2 S3 datastore when that phase is implemented.
7. Restore Scaleway Glacier content only if the local content filesystem is
   unavailable.

For Glacier, list the underlying encrypted S3 object keys, request restoration
with the S3 `RestoreObject` API, wait until each object's restore status is
complete, then use the same rclone crypt password and salt to copy the restored
objects to replacement storage. Restore small groups first to validate the key
material before requesting the entire archive.

## Monitoring and recovery objectives

- Kopia and selected-MinIO copies: target RPO 6 hours; alert after 14 hours.
- Content archive: target RPO 7 days; alert after 9 days.
- Kopia drill: weekly; alert after 14 days without success.
- CNPG drill: monthly; alert after 45 days without success.
- Record restore duration, restored bytes/files, database name, and SQL result
  in Job logs.

The first successful drills establish the measured RTO. Do not claim an RTO
until those results exist.

## Provider comparison

| Provider | Decision |
|---|---|
| Backblaze B2 | Use for mutable operational repositories and drills |
| Scaleway Glacier | Use for encrypted immutable personal originals |
| Scaleway One Zone | More expensive than B2 and only one zone; not selected |
| Scaleway Multi-AZ | Good service, but over twice B2's storage price |
| GCP Archive | Lower idle cost, but substantially higher disaster retrieval cost |
| IDrive e2 | Revisit only if B2 remains above its cost crossover for two billing cycles |
| Cloudflare R2 | No S3 Object Lock and higher storage price |
| Wasabi | One-TB floor and 90-day minimum conflict with current size/pruning |

## Research sources

- [Backblaze B2 pricing](https://www.backblaze.com/cloud-storage/pricing)
- [Backblaze Object Lock](https://www.backblaze.com/docs/cloud-storage-object-lock)
- [Scaleway Object Storage pricing](https://www.scaleway.com/en/pricing/storage/)
- [Scaleway Object Storage regions and classes](https://www.scaleway.com/en/docs/object-storage/concepts/)
- [Scaleway Object Lock](https://www.scaleway.com/en/docs/object-storage/api-cli/object-lock/)
- [Scaleway Glacier restoration](https://www.scaleway.com/en/docs/object-storage/how-to/restore-an-object-from-glacier/)
- [Kopia repository synchronization](https://kopia.io/docs/advanced/synchronization/)
- [CNPG S3-compatible object stores](https://cloudnative-pg.io/docs/1.25/appendixes/object_stores/)
- [Proxmox PBS S3 datastores](https://pbs.proxmox.com/docs/storage.html#datastores-with-s3-backend)
- [Proxmox forum: B2 endpoint settings](https://forum.proxmox.com/threads/pbs-fails-to-connect-to-backblaze-b2.170220/)
- [Proxmox forum: do not raw-copy a live PBS datastore](https://forum.proxmox.com/threads/upload-backups-to-s3-compatible-cloud-storage.160250/)
