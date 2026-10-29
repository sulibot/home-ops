# FileFlows

Internal UI: https://fileflows.sulibot.com

## Initial setup, 2026-10-28

- One server/internal agent, using the vendor's pinned `modded-26.10-stable` image.
- `gateway-internal` only; no public tunnel route.
- Explicit Kestrel IPv6 listener is required for this cluster's IPv6-first probes.
- Configuration: `fileflows-config`, 2 GiB CephFS, with VolSync/Kopia backups every
  three hours in a dedicated slot, matching the repository's Ceph load controls.
- Work/review: `fileflows-work`, 100 GiB CephFS, mounted at `/temp` and `/review`.
  This is temporary review storage and is not included in configuration backups.
- Initial content was mounted **read-only** at `/data`, both in the volume and
  container mount definitions. The server process runs as UID/GID 1000 after the
  vendor entrypoint initializes it.
- The initial setup was paused with no libraries; see the production section
  below for the replacement workflow now authorized.

The initial resources were applied from the local checkout to let the Helm
controller install the application. The tier-2 application Kustomization now
includes this directory so Flux can maintain the deployment after merge.

## Review workflow

The UI contains `DRAFT - SDR H264 to HEVC review copies`; its portable export is
`flows/hevc-review-draft.json`. Importing it does not enable processing.

After the final restart, the application was Ready, still paused, and contained
zero library files. FFmpeg, FFprobe, and the CPU `libx265` encoder are available.
The final configuration backup completed successfully at 21:50 UTC on 2026-10-28.
A restore has not been tested.

1. Read video metadata; stop on read failure.
2. Continue only for H.264.
3. Skip HDR for the initial trial. HDR handling needs a separate validated flow.
4. Start the FFmpeg builder and choose MKV.
5. Encode the video as CPU HEVC 10-bit, quality 7/9, speed 2/5.
6. Execute with hardware decoding disabled; stop on failure.
7. Copy the working result to `/review` with a `.HEVC-REVIEW.mkv` suffix.

There are no scale, crop, frame-rate, audio-removal, subtitle-removal, library
output, original replacement, or deletion nodes. No app refresh is attached to
this trial: it creates separate review copies, not changes to managed libraries.
The quality/speed numbers are FileFlows presets, **not CRF values**.

## Read-only checklist findings

Inventory is from Sonarr/Radarr media metadata; no bulk re-analysis or search was
triggered. Counts refer to files, not necessarily individual episodes.

| Codec family | Movie files | TV files |
| --- | ---: | ---: |
| HEVC/H.265 | 114 | 918 |
| AVC/H.264 | 32 | 994 |
| AV1 | 2 | 16 |
| VC-1 | 0 | 1 |
| Unknown | 1 | 0 |

- All 2,078 tracked file paths were stat'ed successfully; none had multiple hard
  links at the time of inspection. Both managers nevertheless have hardlink
  imports enabled, so future files may be linked.
- Media analysis is enabled and rescan-after-refresh is `always` in both apps.
- Plex, Sonarr, Radarr, and FileFlows share `/data/media/movies-4k` and
  `/data/media/tv-4k`; no path mapping is required between these mounts.
- Read-only FFprobe checks as UID 1000 succeeded on an H.264 film, a 4K
  HEVC HDR film, and Invincible S01E01. The latter is 1080p H.264/BT.709,
  with three E-AC-3 audio tracks, 19 subtitle tracks, and 25 chapters. This
  establishes readable source metadata, not conversion or playback quality.
- Subtitle metadata is populated for 143 movie and 1,820 TV files. Missing
  metadata is not proof of missing subtitles.
- HDR metadata includes HDR10, HDR10+, Dolby Vision combinations, and HLG.
  Do not treat every file lacking cached HDR metadata as proven SDR.
- No snapshots were listed in the `.snap` directories at `/data`, `/data/media`,
  or either active library root. Ancestor snapshots, backups, and other retained
  copies were not exhaustively audited.

## Production setup, 2026-10-29

The user approved production replacement. The initial trial reduced Invincible
S01E01 from 2.03 GB to 1.28 GB (37%). Full video/audio decoding, non-video payload
hashes, duration, video properties, chapters and track metadata passed. A lost
original-language subtitle flag was repaired with a stream-copy remux. Actual
Apple TV playback and subjective picture quality have not been confirmed.

The production worker subsequently replaced that episode, verified Sonarr file
2583 for series 107, refreshed/renamed it to x265, requested Plex section 1 refresh,
and removed both the original rollback link and review copy. Saved 753,226,568
bytes. A manual run through the imported production flow then successfully skipped
the now-HEVC file, confirming the FileFlows-to-worker integration.

`flows/hevc-production.json` invokes the versioned `app/resources/production.py`
through FileFlows' Function node. Library discovery and queue state are managed
in the UI and backed up with FileFlows' configuration; the worker and flow export
are in Git. Reimport the export after changing its Function code. Script changes
are deployed through the generated ConfigMap and reloader.

- Production media is writable. One internal runner; global worker lock prevents
  concurrent replacements. CPU limit is four cores, memory limit 2 GiB.
- Scope: H.264 SDR MKV files in movies-4k and tv-4k. Existing HEVC, AV1, HDR,
  unknown SDR, other containers, multiple-video streams and hardlinks are skipped.
- Libraries scan every three hours and watch filesystem events. File Type is
  `Custom` with extension `mkv`, avoiding FileFlows' slow video-info detection
  during discovery on CephFS. The worker probes each file before processing.
  `Skip File Access Tests` is also enabled; that setting alone did not resolve
  the scan delay. The worker performs real I/O, validation and source checks.
- Files modified within two hours or playing in Plex are deferred with an error.
- CPU x265 Main10, CRF21, slow preset; no scaling or frame-rate changes. Explicit
  stream mapping and dispositions preserve audio, subtitles, attachments and chapters.
- Encode into a hidden `.partial` file beside the source on CephFS. Require at
  least 5% savings, matching metadata and non-video stream hashes, and a full
  video/audio decode. Recheck source identity, manager file ID and Plex playback.
- Retain a temporary hardlink to the original inode during atomic replacement.
  Refresh and rename the affected title through Sonarr/Radarr, then request a
  targeted Plex scan. Remove the old inode only after those steps succeed.
- No monitoring or quality-profile changes: wanted 1080p-to-4K upgrades remain enabled.
- Secrets are injected from existing Kubernetes Secrets; no API keys in exports.

### Failure recovery

Inspect `/app/Data/Production/*.json` and the FileFlows job log. A journal in
`committing`, `replaced`, or `refreshing` blocks further eligible conversions and
retains the `.fileflows-<id>.original` hardlink for recovery. Pause processing,
verify the live manager path and journal identities, then either finish refresh
and remove that rollback link or restore it to the managed path and refresh.
Do not blindly delete journals or rollback links. A pre-commit validation failure
removes its partial output and leaves the source intact. A pod killed during
encoding can leave a `.partial` file, which can be removed after confirming the
worker is stopped and the source remains intact.

The temporary rollback link is not a long-term backup. Existing snapshots or
other backups can delay reclaimed space. The pre-production FileFlows SQLite
backup is `/app/Data/Backups/pre-production-20261028.sqlite`.

### Scanner configuration repair

FileFlows 26.10.9 threw `InputListString.Add` / `NullReferenceException` when
entering the first custom extension in a library whose `Extensions` list was
absent. Both production libraries were repaired while the deployment was stopped,
after a SQLite backup to
`/app/Data/Backups/pre-extension-repair-20261029.sqlite`. Their library JSON now
contains `FileTypes: 7` (Custom) and `Extensions: ["mkv"]`. No other database
rows were changed; SQLite integrity passed. If restoring an older configuration,
check these fields before resuming discovery. Never edit the live database.

Run the destructive-operation safeguards locally with:

```sh
cd kubernetes/apps/tier-2-applications/fileflows/app/resources
python3 -m unittest -v test_production
```
