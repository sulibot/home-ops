# Eufy S1 Pro activity and resume repair

The `damacus/robovac` v2.5.2 integration was receiving data from the S1 Pro
(`T2080A`) at `10.31.0.149`, but interpreted DPS 6 as activity. On this unit
that value advances with elapsed cleaning minutes. DPS 153 carries the actual
activity. The user also reported that Play made a locator-like sound instead
of resuming a paused job. The installed model used DPS 160 for start/pause.

## Upstream evidence

- [Issue 443](https://github.com/damacus/robovac/issues/443) describes commands
  accepted without effect on this exact model. Its proposed DPS 160 controls
  and DPS 6 activity mapping were incorporated in
  [PR 530](https://github.com/damacus/robovac/pull/530) and were already present
  locally. The issue remains open for unverified dock/locate commands. It is
  related evidence, not confirmation of the exact sound or a sufficient fix
  for this unit.
- The [S1-specific integration](https://github.com/tkoba1974/ha-eufy-robovac-s1-pro/blob/main/custom_components/eufy_robovac_s1_pro/vacuum.py)
  uses protobuf DPS 152 commands: `AA==` for auto-clean, `AggN` for pause and
  `AggO` for resume. The native pause response captured on this unit also
  contained method 13; its activity was `CAoAEAUyAggB` (Paused).
- [S1 issue 24](https://github.com/tkoba1974/ha-eufy-robovac-s1-pro/issues/24)
  reports that after restart only scalar data points arrive until a state
  change. We reproduced missing DPS 152/153 on startup and on explicit query.
- [S1 issue 18](https://github.com/tkoba1974/ha-eufy-robovac-s1-pro/issues/18)
  reports incorrect activity decoding on another firmware. Status payloads
  can vary; copying another integration wholesale is not a verified fix.

## Applied repair

- T2080A uses the existing T2080 DPS 153 status mapping and activity table.
- T2080A start/pause use DPS 152, with Resume selected for a paused job.
- Missing S1 status stays unknown rather than being guessed as idle. Play in
  that condition sends Resume, avoiding an accidental new cleaning cycle.
  A truly docked unit with missing status may therefore need a status change
  before a new clean can be started from HA; this path is not validated.
- Generic pause only writes commands the model declares. Legacy boolean
  start/pause behavior remains unchanged.
- Protocol 3.3, fan-speed, battery and advertised feature flags are unchanged.
- Removed orphaned restored `sensor.robovac_error` after finding no automation,
  script or dashboard references. This does not add physical fault monitoring.

## Validation

- Before installation, exercised the changed Python methods with fake devices:
  paused Resume, confirmed idle Start, unknown-state Resume, no false idle from
  partial S1 data, Pause, and legacy start/pause. No device writes in those tests.
- One direct Resume produced DPS 153 `BgoAEAUyAA==` (Auto Cleaning), and HA
  reported `cleaning`.
- After the final patch and HA restart, tested the actual HA service path:
  `vacuum.pause` -> `paused`, then `vacuum.start` -> `cleaning`.
  This is the same service used by the Play button. The test left it cleaning.
- Fresh start from dock, return-to-dock, room cleaning and fault reporting
  were not physically validated. Dock/locate remain unadvertised.

## Persistence and rollback

The patch is tracked in `scripts/patches/robovac-t2080a-status.patch` and is
applied to the HA config PVC under `/config/custom_components/robovac/`.
It changes `vacuums/T2080A.py` and `vacuum.py`. HACS can overwrite these files.
Review upstream changes before reapplying; this is not an automatic deployment
hook. The patch uses zero context (`git apply --unidiff-zero`).

Original files for full rollback:

- `/config/backups/robovac-s1-status-20261116/T2080A.py`
- `/config/backups/robovac-s1-control-20261116/vacuum.py`

Restore both originals, then restart HA to reload Python. Additional staged
backups are in `/config/backups/robovac-s1-control-final-20261116/`.
The removed entity record is backed up at
`/config/backups/robovac-stale-error-20261116.json`.
