# Home Assistant Wall Switch Matter Bulb Reliability

## Status

Open.

## Context

Home Assistant on cluster-104 uses Matter Kasa wall dimmers to control IKEA
KAJPLATS Matter bulbs in these rooms:

- Living Room: `light.living_room_switch` controls `TV right`, `Couch left`, and `Couch right`.
- Master Bedroom: `light.master_switch` controls `Bed left` and `Bed right`.
- Sebby Bedroom: `light.bedroom_switch` controls `Sofa_left`, `Sofa_right`,
  `Standing_lamp_1`, and `Stadning_lamp_2`.

The immediate Home Assistant YAML issues have been corrected:

- Template room lights now default `brightness` to `255` instead of passing
  `none` to `light.turn_on`.
- Wall-switch mirror automation targets individual reachable bulbs instead of
  the aggregate template light.
- Wall-switch brightness changes are mirrored separately.
- Monitoring creates a persistent notification and system log warning when
  controlled Matter bulbs are unavailable or when reachable targets do not
  follow a switch state change.

## Observed Failure

On 2026-07-20, HA received master bedroom wall-switch events. Automation traces
showed `light.master_switch` changing state and the mirror automation running.
The reachable target list contained only `light.kajplats_e26_ws_globe_1600lm_5`
because `Bed left` was unavailable.

Matter server logs showed repeated `peer-unresponsive`, failed probe, and CASE
session timeout events for several nodes. The OTBR was online as a Thread
router, but the neighbor table had multiple weak links around -79 to -90 dBm,
including at least one link with `LQ In` of 1.

Current symptom is therefore not only an HA automation bug. The remaining issue
is Matter/Thread reachability and command latency for the bulbs.

## Risk

Wall switches may appear to fail even when HA received the switch event, because
the target smart bulbs are unavailable or slow to accept Matter commands.
Rapid button presses can also produce stale queued commands if automations queue
instead of letting the latest switch state win.

## Desired End State

- All wall-switch-controlled bulbs remain reachable through Matter.
- Wall-switch state changes affect every reachable bulb in the room within a few
  seconds.
- HA displays a persistent warning when controlled bulbs are unavailable.
- Long-term dashboards/alerts make Matter/Thread degradation visible before it
  breaks day-to-day controls.

## Follow-Up Work

- Map each Matter node ID to room/device name so Matter server logs can be read
  without guessing.
- Improve Thread mesh placement or add powered Thread routers near weak rooms.
- Confirm the Kasa dimmers are not cutting power to smart bulbs in a way that
  breaks Matter reachability.
- Consider replacing load-controlling smart dimmers with scene-controller or
  detached-mode controls for smart bulbs, or use dumb dimmable bulbs behind
  Kasa load dimmers.
- Add Prometheus or HA sensor-based monitoring for:
  - Count of unavailable wall-switch-controlled lights.
  - Matter server `peer-unresponsive` events.
  - OTBR neighbor links with weak RSSI or low link quality.
