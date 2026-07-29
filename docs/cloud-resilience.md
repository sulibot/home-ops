# Cloud resilience: KMS and offsite backup

## Decision

Use a cost-optimized three-tier design across the two personal cloud providers
that are actually useful for this stack:

| Tier | Data | Provider | Expected cost |
|---|---|---|---|
| Local | Fast operational restore | Existing Ceph, then local PBS | Already owned |
| Hot offsite | PBS and Kopia repositories | Backblaze B2 | $6.95/TB-month, metered with no 1 TB floor |
| Cold offsite | Raw photos and home movies; optionally music | GCP Cloud Storage Archive in `us-west1` | About $1.20/TiB-month |
| Root of trust | OpenBao auto-unseal | GCP Cloud KMS | About $0.06/month for one active software key version |

Movies and TV are deliberately excluded. They are replaceable and dominate the
media footprint. Derived Immich thumbnails and encoded video are also excluded;
archive only originals plus the database/configuration needed to reconstruct
the library.

GCP is the right cold provider at the current size because the account is
already required for the inexpensive OpenBao seal. The live eligible set is
about 60 GiB of Immich library plus 88 GiB of personal video. Music would add
about 184 GiB. Archive storage is therefore roughly:

- $0.18/month for photos and personal video;
- $0.40/month with music;
- $0.24 or $0.46/month respectively after adding the one KMS key version.

AWS Glacier Deep Archive stores data for about $1/TB-month, but adding AWS KMS
would make the all-AWS design more expensive until the cold set reaches roughly
4.5 TB. Keeping GCP KMS and adding AWS only for today's archive would save less
than $0.10/month while adding another account and recovery path. Re-evaluate
AWS Glacier Deep Archive when irreplaceable cold data approaches 4 TB.

Backblaze B2 cannot replace Cloud KMS because it does not offer an
OpenBao-supported seal endpoint. GCP Archive cannot replace B2 for a live
PBS/Kopia repository because its 365-day minimum duration and retrieval charges
conflict with routine reads, pruning, and garbage collection.

## Evidence from the live stack

The deployed backup paths remain inside the homelab failure domain:

- Proxmox retains about 665.6 GB of complete `vzdump` archives on CephFS.
- The most recent backup per guest totals only about 79.9 GB; the retained
  footprint is large because each daily archive is another full image.
- MinIO holds about 54 GB, including S3-backed application backups.
- Kubernetes exposes three 200 GiB Kopia PVCs backed by local CephFS.
- The shared content filesystem contains about 8.6 TiB, but almost all of that
  is replaceable movies and TV.
- The B2 account and empty buckets exist, but there is no active offsite job.

Ceph replication protects against disk and node failure, not fire, theft,
operator deletion, Ceph corruption, or a site-wide electrical event.

## Tier 0: local PBS

Deploy Proxmox Backup Server 4.2 as a small VM with two datastores:

1. a local datastore on a Ceph-backed virtual disk for fast restores;
2. a B2 S3 datastore with a dedicated 128 GiB persistent cache.

Back up guests to the local datastore and use a PBS local sync job to populate
the B2 datastore. PBS sends incremental, deduplicated chunks, so B2 should be
much closer to the roughly 80 GB current working set plus retained deltas than
the 665.6 GB `vzdump` footprint. Treat that as a hypothesis until the first
month is measured.

Do not `rclone` a live PBS datastore. PBS owns chunk ordering, pruning, and
garbage collection. A file-level copy of an active repository can be
inconsistent.

## Tier 1: Backblaze B2 hot backup

Use separate buckets and separate application keys:

1. `sulibot-pbs-offsite`
   - No Object Lock and no bucket versioning; PBS garbage collection needs
     list/get/put/delete.
   - PBS client-side encryption.
   - Bucket-scoped key, never the B2 account master key.
   - Configure PBS with path-style addressing and the
     `Skip If-None-Match` provider quirk.
2. `sulibot-kopia-offsite`
   - Kopia client-side encryption.
   - Bucket-scoped read/write/list/delete key for repository maintenance.
   - Repository password in 1Password plus an offline recovery copy.
3. `sulibot-infrastructure-immutable`
   - Object Lock with a short governance retention period.
   - Upload-only key without delete, retention-management, or
     governance-bypass capabilities.
   - Terraform state copied from the dedicated GCS backend every six hours,
     encrypted OpenBao Raft snapshots, RouterOS exports, recovery manifests,
     and other small break-glass artifacts.

Terraform state is authoritative in the regional Standard-class
`sulibot-terraform-state` GCS bucket, not in MinIO or the Archive-class content
bucket. The `gcs-terraform-state-offsite-copy` CronJob uses a separate
read-only GCS identity and an upload-only B2 identity; it never synchronizes
deletions. See `docs/runbooks/terraform-state-gcs.md`.

The existing B2 master-capability credential in 1Password is for account
administration only. Do not install it in PBS, Kubernetes, an LXC, or
OpenBao.

At current pricing, copying all 665.6 GB of retained `vzdump` data raw would
cost about $4.63/month; adding 54 GB would put the upper bound near
$5.00/month. The PBS design should be materially lower. B2 remains cheaper than
IDrive e2's $4 monthly/1 TB floor while actual offsite usage stays below about
576 GB. Re-evaluate only after two complete billing cycles above that point.

## Tier 2: GCP Archive for personal originals

Use a separate `sulibot-personal-archive` project under the same personal GCP
billing account as the KMS project:

- single-region `us-west1` Archive bucket;
- public access prevention and uniform bucket-level access;
- a one-year retention policy, left unlockable until a restore drill passes;
- an uploader principal that can create/read/list but cannot delete objects or
  administer retention;
- client-side encryption with the recovery identity stored in 1Password and an
  independent offline copy;
- append-only, date-and-content-hash-named archive batches with encrypted
  manifests and checksums.

Do not point Restic, Kopia, or PBS directly at the Archive bucket. Upload frozen
archive batches instead. This avoids routine metadata reads, object rewrites,
and early-deletion charges. Archive:

- Immich originals under the library/upload paths;
- personal home-video originals;
- music only if losing or re-ripping it would be costly.

Exclude Immich thumbnails, transcoded video, caches, torrents, movies, TV, and
all other reproducible data.

GCP Archive data is online but charges about $0.05/GiB to read and has a
365-day minimum duration. This is disaster insurance, not the first restore
target.

## Provider comparison

| Provider | Fit | Decision |
|---|---|---|
| Backblaze B2 | Proven PBS-compatible hot S3, no storage floor, 3x stored data in free egress | Use for live offsite repositories |
| IDrive e2 | $4/TB but a $4/1 TB monthly minimum | Revisit only if deduplicated B2 stays above 576 GB |
| MEGA S4 | PBS guide and low marginal rate, but the plan starts around EUR 15 for 3 TB | Too expensive at the current footprint |
| Storj | Recent price/minimum changes and no advantage over B2 for this size | Reject |
| GCP Archive | Cheapest operationally simple cold tier because GCP is already needed | Use for personal originals |
| AWS Glacier Deep Archive | Slightly cheaper per TB, 12-48 hour restore, 180-day minimum, costly recovery | Revisit near 4 TB of cold originals |

## Recovery order

1. Recover internet, DNS, the operator workstation, and 1Password access.
2. GCP Cloud KMS automatically unseals the OpenBao members as they start.
3. Restore infrastructure credentials and configuration from 1Password/Git.
4. Recreate PBS with its persistent cache and reuse the B2 S3 datastore.
5. Restore OpenBao snapshots, critical guests, and Kopia application data.
6. Restore GCP Archive media only if the local and B2 copies are unavailable.
7. Validate recovery without relying on credentials stored only inside
   OpenBao.

Keep the GCP service-account JSON, B2 application keys, PBS/Kopia encryption
keys, OpenBao recovery shares, and SOPS identities available through
independent break-glass paths. OpenBao must not be required to retrieve the
credentials needed to unseal OpenBao or restore its own backup.

## Research sources

- [Backblaze B2 pricing](https://www.backblaze.com/cloud-storage/pricing)
- [GCP Cloud Storage pricing](https://cloud.google.com/storage/pricing)
- [GCP Cloud KMS pricing](https://cloud.google.com/kms/pricing)
- [AWS Glacier storage classes](https://aws.amazon.com/s3/storage-classes/glacier/)
- [PBS 4.2 S3 datastore documentation](https://pbs.proxmox.com/docs/storage.html#datastores-with-s3-backend)
- [Proxmox forum: Backblaze B2 endpoint settings](https://forum.proxmox.com/threads/pbs-fails-to-connect-to-backblaze-b2.170220/)
- [Proxmox forum: why not to copy a live PBS datastore with rclone](https://forum.proxmox.com/threads/upload-backups-to-s3-compatible-cloud-storage.160250/)
- [Homelab forum: 2025 offsite backup approaches](https://www.reddit.com/r/homelab/comments/1k1cusq/)
- [DataHoarder forum: 2025 low-cost provider discussion](https://www.reddit.com/r/DataHoarder/comments/1m8flvt/)
