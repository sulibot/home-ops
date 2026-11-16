# Eufy S1 Pro activity reporting

The `damacus/robovac` v2.5.2 integration was receiving live data from the
S1 Pro (`T2080A`) at `10.31.0.149`, but its model definition interpreted
DPS 6 as activity. The observed value advanced through 1, 2 and 4, producing
Cleaning, Paused and Unknown in Home Assistant. DPS 153 simultaneously
reported `BgoAEAUyAA==`, which the integration's existing T2080 definition
decodes as Auto Cleaning. DPS 6 is the cleaning-time counter in that definition.

## Repair

- Backed up and removed `sensor.robovac_error`, an orphaned restored entity.
  The T2080A model does not expose an error sensor. No automation, script or
  dashboard references were found. This removes a stale tile; it does not
  add fault monitoring or claim that the robot has no physical errors.
- Patched only T2080A's status reading to use T2080's DPS 153 mapping and
  corresponding activities. The protocol version, feature flags, battery,
  fan-speed and command-writing definitions remain unchanged.
- Verified decoding of cleaning, paused, docked and returning payloads and
  equality of every unchanged command definition before applying.
- Restarted Home Assistant to load the Python change. No start, pause, stop,
  dock, fan-speed or other physical vacuum commands were sent.
- After startup and a read-only refresh, `vacuum.robovac` reported `idle`
  and `sensor.robovac_battery` reported `100`. The orphaned Error entity
  remained absent. Control commands were not exercised.

The original model is backed up on HA's PVC at
`/config/backups/robovac-s1-status-20261116/T2080A.py`.
The removed entity record is in
`/config/backups/robovac-stale-error-20261116.json`.

The narrow patch is tracked in
`scripts/patches/robovac-t2080a-status.patch`. It was applied to
`/config/custom_components/robovac/vacuums/T2080A.py`, not to the container image.
HACS updates may overwrite it. Review the model after an integration update;
do not blindly apply this patch if upstream has changed the same code.
To roll back, restore the backed-up model and restart HA.

Upstream sources:

- [T2080A v2.5.2](https://github.com/damacus/robovac/blob/v2.5.2/custom_components/robovac/vacuums/T2080A.py)
- [T2080 v2.5.2](https://github.com/damacus/robovac/blob/v2.5.2/custom_components/robovac/vacuums/T2080.py)

This repair does not validate control commands or add unsupported S1 Pro
features. The native Eufy app remains necessary for features this integration
does not expose, including detailed fault diagnostics.
