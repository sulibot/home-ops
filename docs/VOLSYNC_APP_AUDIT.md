# Stateful application backup coverage audit

Audited: 2026-07-29

This audit joins live PVC mounts, live VolSync `ReplicationSource` objects,
cluster-104 backup CronJobs, CNPG/Barman, shared content mounts, and the
off-site recovery targets. Counting only existing VolSync objects is
insufficient because an application with no object would be invisible.

## Result

- All 46 live cluster-101 VolSync sources passed presence, freshness under 25
  hours, non-empty content, zero source errors, and a repository-wide 1% file
  integrity sample on 2026-07-29.
- This change added the two mounted application PVCs that were missing from
  the prior 44-source set: Notifiarr and OpenCloud.
- Home Assistant, Music Assistant, and Matter Server on cluster-104 have
  separate application-consistent Kopia CronJobs because their local-path
  volumes cannot use cluster-101 VolSync snapshots.
- PostgreSQL, shared personal content, the Kopia repository, and OpenBao Raft
  are protected through purpose-specific paths described below.
- No mounted application state remains unintentionally uncovered after this
  change.

## Cluster-101 application PVCs

The verified VolSync set is:

| Namespace | Sources |
|---|---|
| `default` | Actual, Atuin, Audiobookshelf, Aurral, Autobrr, Baserow, Bookshelf, Calibre Web Automated, CloudBeaver, Cross-seed, Digarr, FileBrowser, Firefly III, FreshRSS, Grimmory, Immich machine-learning config, Karakeep, LazyLibrarian, Lidarr, MediaSage, Multi Scrobbler, n8n, NZBGet, Ollama, Paperless, Paperless GPT, Plex, Prowlarr, qBittorrent, Qui, Radarr 4K, Seerr, Shelfmark, Slskd, Sonarr 4K, SoulSync, Sportarr, Tautulli, Twenty, Vikunja, Whisparr |
| `observability` | Gatus, Grafana |

This pull request additionally enables:

| App | Source PVC | Schedule | Reason |
|---|---|---|---|
| Notifiarr | `notifiarr` | hourly at minute 44 | Mounted application configuration was not represented by any source |
| OpenCloud | `opencloud-config` | hourly at minute 51 | Identity, metadata, and NATS-backed application state are not fully reconstructable from Git and user files |

The verifier queries the Kubernetes API for the complete live source set on
every run. Removing a source therefore causes a failure instead of silently
reducing the expected count.

## Purpose-specific coverage

| Data | Protection path | Off-site path |
|---|---|---|
| CNPG `postgres-vectorchord-1` | Barman base backups and WAL in MinIO | Logical copy to `sulibot-cnpg-offsite`, then disposable SQL restore |
| `/content/users` | Shared CephFS user data | Client-side encrypted GCS Archive allowlist |
| Immich originals/uploads/profiles | Shared CephFS content plus fresh database dumps | Client-side encrypted GCS Archive allowlist and real-original restore drill |
| Music, audiobooks, books | Shared CephFS content | Client-side encrypted GCS Archive allowlist |
| VolSync Kopia repository | Application snapshots in MinIO | Native repository synchronization to `sulibot-kopia-offsite` |
| OpenBao | Proxmox guest backup plus six-hour application-consistent Raft snapshot | Direct upload from the active leader to the 30-day-governance infrastructure bucket |
| Terraform state currently in MinIO | Logical S3 object copy | 30-day-governance infrastructure bucket |
| Home Assistant | Daily read-only Kopia snapshot including root-owned OTBR state | Same encrypted Kopia repository, then B2 repository synchronization |
| Music Assistant | Daily read-only Kopia snapshot as application UID/GID | Same encrypted Kopia repository, then B2 repository synchronization |
| Matter Server | Daily read-only Kopia snapshot of `/data` | Same encrypted Kopia repository, then B2 repository synchronization |

## Deliberate exclusions

These mounted PVCs are not application recovery sources:

- Valkey PVCs are rebuildable cache/session data; authoritative application
  records live in CNPG or application PVCs.
- Prometheus, Loki, Tempo, VictoriaLogs, Alertmanager, and Fluent Bit state are
  disposable telemetry. Grafana configuration is backed up separately.
- VolSync cache/destination PVCs are derived recovery machinery, not primary
  data.
- The local Kopia PVC is the repository being replicated, so recursively
  snapshotting it through VolSync would be incorrect.
- Movies, TV, sports, `vids`, downloads, Immich thumbnails, and encoded video
  are explicitly outside the approved content allowlist.

## Orphaned PVCs

The live cluster still contains unmounted legacy PVCs for retired or migrated
workloads, including old Cross-seed, Home Assistant, Navidrome, NZBGet,
Omada, Overseerr, Plex, qBittorrent, Radarr, and Sonarr claims. They are not
active backup gaps. Delete them only through a separate retention-reviewed
cleanup because an unmounted PVC may still be intentionally retained.

## Verification

Run the fleet verifier:

```bash
kubectl create job -n volsync-system \
  --from=cronjob/volsync-backup-verifier \
  volsync-backup-verifier-audit
kubectl logs -n volsync-system -f job/volsync-backup-verifier-audit
```

A valid run must report the same number of expected and verified sources,
zero coverage/freshness/source errors, and a successful repository integrity
sample. Provider copy and restore freshness are monitored separately by the
off-site backup rules and dashboard.
