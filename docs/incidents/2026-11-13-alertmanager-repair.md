# Alertmanager repair, 2026-11-13

## Findings and changes

- Alertmanager was healthy but repeatedly truncated Pushover messages to 1,024
  characters. Messages now contain at most three bounded summaries, with the
  existing Alertmanager link for complete details. Unicode stress tests stayed
  at or below 890 characters through 1,000 alerts.
- Sixteen retained failed Jobs and five mount-doctor alerts represented old
  failures despite subsequent successful CronJob runs. New rules use terminal
  failure conditions and exclude runs superseded by the owner's last success.
  Failed standalone Jobs, never-successful CronJobs, and new failures still
  alert. Retained Job evidence was not deleted.
- Staging database rules targeted the retired CNPG instance. They now monitor
  `context-fabric-supabase-db`, its actual database PVC, and the daily
  `context-fabric-snapshot` CronJob. A readiness probe uses `pg_isready` without
  adding a database-restarting liveness probe. The current deployment has no
  PostgreSQL SQL-metrics exporter; these checks cover availability, volume
  capacity, and snapshot job success/freshness. Database and storage snapshots
  from 2026-11-13 03:30 UTC were Ready before rollout.
- Changes and regression tests are in PR #544.

## Ceph mitigation and remaining verification

All 21 OSDs were up/in, all four filesystems healthy, and placement groups had
no degraded data. Six HDD-backed OSDs retained BlueStore slow-operation warnings.
SMART checks passed on affected physical disks; sampled OSD latency and host
I/O pressure had recovered by investigation time.

Logs recorded 5.27-second and 6.64-second BlueStore operations at 03:31–03:33 PST.
The three hosts were simultaneously backing up workers to CephFS during that
window, with individual backups reading/writing over 100 MiB/s. This is a likely
contention source, not proof of a single exclusive cause; scrubbing was also
active and multiple OSDs share each HDD.

Applied `bwlimit=32768` (KiB/s, 32 MiB/s) to Proxmox backup job
`daily-all-guests` through the API and recorded the same setting in Terragrunt.
The schedule, retention, guest list, and existing worker limit remain intact.
This limits each backup task; it is not a cluster-wide 32 MiB/s aggregate cap.
The next scheduled run must confirm successful completion and reduced latency.
Rollback is `pvesh set /cluster/backup/daily-all-guests --bwlimit 0` plus reverting
its Terragrunt value if the limit proves inappropriate.

The existing BlueStore warning lifetime is 86,400 seconds. No warnings were
muted, thresholds weakened, OSDs restarted to clear history, or scrubs disabled.
A retained warning can persist after current latency recovers.

## Home Assistant physical-device follow-up

Reloaded the existing Matter and Sonos integrations through the authenticated
Home Assistant API. Both reloads succeeded. The master-bedroom mismatch cleared,
but a living-room mismatch appeared. Inspection showed the existing brightness
automation treated reconnection as a brightness adjustment and invoked
`light.turn_on`. PR #546 adds a guard against missing/unknown/unavailable prior states. Nine
condition tests passed; cluster-104 deployed it and the live condition was read
back after rollout. The automation file is a ConfigMap subPath mount, so the
initial attempt to save through the HA API returned `EBUSY`; it was deployed
through GitOps instead. No direct light commands were sent.

The following remained unavailable after reload:

- Sebby Bedroom Sofa Left, Standing Lamp 1, Standing Lamp 2
  (`light.kajplats_e26_ws_globe_1600lm_6`, `_8`, `_9`).
- Master Bedroom Green Button, including its battery telemetry.
- Dining Room Sonos Play:3 (`00:0e:58:fb:39:8a`, last known IP `10.30.0.62`).
  The router reports failed ARP, three pings timed out, and TCP port 1400 was
  unreachable from Home Assistant. Both Sonos and Music Assistant agree it is
  offline.

The Thread border router was online as leader. Its neighbor table included a
weak -89 dBm / link-quality-1 neighbor alongside healthy links. Device power,
battery, and Thread placement need physical checks if these devices do not
recover. Commissioning records were preserved. Alerts remain active because
these are real reachability failures, not notification defects.


## Deployment follow-up

Two live resources (`cross-layer-storage-rules` and AlertmanagerConfig
`alertmanager`) had `kustomize.toolkit.fluxcd.io/reconcile=disabled` annotations.
After comparing live/repository specifications, restored reconciliation. The
Alertmanager override had Linear delivery paused and critical email enabled;
PR #546 preserves those effective routes in Git before restoring management.
The notification template was first narrowly patched without changing routes.

Alertmanager also warned that Watchdog inherited a 5-minute group interval,
which overrode its intended 2m30s repeat interval. Its group interval now
explicitly matches the 2m30s repeat interval.

## Plex OOM mitigation

During verification Plex hit its 6 GiB limit again at 12:24:24 UTC. Metrics
showed a similar spike before the preceding restart at 11:55 UTC. Logs showed
loudness analysis repeatedly stuck on movie item 8516, John Carter, followed by
`udc input failed` messages. This is consistent with the reported Plex loudness
analysis memory issue; the specific decoder fault is not independently proven.

Disabled `enableLoudnessAnalysis` through Plex's supported library preferences
API for Movies (3), TV Shows (1), and Sports (8), then read back `false` for all
three. Music/audio analysis and other scheduled maintenance remain enabled.
This stops new video loudness measurements, so loudness normalization may be
unavailable on videos not already analyzed. Existing measurements remain.
No media files or library records were removed, and the 6 GiB memory cap remains.
The in-flight analysis was not API-cancellable. With zero active playback
sessions, restarted Plex once to terminate it and load the saved preferences.
Re-enable these per-library preferences after a fixed Plex version is verified.

References:
- [Plex audio enhancement settings](https://support.plex.tv/articles/audio-track-enhancements-for-video/)
- [Plex report of loudness-analysis memory growth](https://forums.plex.tv/t/loudness-analysis-grows-to-10-gb-ram-and-triggers-host-oom-killer/943677)
