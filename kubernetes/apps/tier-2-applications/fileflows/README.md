# FileFlows

Internal UI: https://fileflows.sulibot.com

## Initial setup, 2026-10-28

- One server/internal agent, using the vendor's pinned `modded-26.10-stable` image.
- `gateway-internal` only; no public tunnel route.
- Explicit Kestrel IPv6 listener is required for this cluster's IPv6-first probes.
- Configuration: `fileflows-config`, 2 GiB CephFS, with hourly VolSync/Kopia backups.
- Work/review: `fileflows-work`, 100 GiB CephFS, mounted at `/temp` and `/review`.
  This is temporary review storage and is not included in configuration backups.
- Production content is mounted **read-only** at `/data`, both in the volume and
  container mount definitions. The server process runs as UID/GID 1000 after the
  vendor entrypoint initializes it.
- Processing is paused indefinitely in the application. No library is assigned
  to the draft flow and no files have been queued.

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

## Before any conversion is enabled

The user has requested setup and inspection, not execution of conversion jobs.
Keep processing paused and the production mount read-only.

An approved trial must use a few explicitly selected files. Verify encoder
availability, sufficient staging space for simultaneous temporary/review copies,
decoding, duration/sync, resolution, frame rate, audio/subtitle/attachment/chapter
preservation, output size, and actual playback on the Apple TV/Samsung. Visually
compare dark scenes, grain, animation, and motion. There is no claim yet that
these presets meet the user's picture-quality or storage targets.

Production replacement, concurrent-upgrade checks, app notifications, automatic
validation, and rollback are a separate step. They are intentionally absent from
this review-copy draft. Do not unmonitor titles globally: preserve wanted 4K
upgrades from 1080p fallback releases.
