# Home Assistant Wall Switch Matter Bulb Reliability

## Status

Open.

Monitoring implemented for the Home Assistant control path. The remaining open
work is deeper Matter/Thread mesh quality visibility, local PV backup coverage,
and the physical reliability work implied by those signals.

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
- Home Assistant exports a narrow Prometheus metric set for the wall-switch
  control path through `/api/prometheus`.
- Prometheus on the main observability cluster scrapes cluster-104 Home
  Assistant through `hass-app.sulibot.com`.
- Alertmanager rules now cover Home Assistant scrape loss, disabled
  wall-switch automations, unavailable controlled bulbs, switch/target state
  mismatch, and follow-failure counter increments.
- Home Assistant exports button, music-player, and config-volume health sensors:
  - IKEA BILRESA button event freshness.
  - IKEA BILRESA button battery low/unavailable counts.
  - Music Assistant/Sonos core player availability.
  - Music-script target availability.
  - Home Assistant `/config` disk usage/free-space.
- Gatus checks now include `ha-google.sulibot.com/api/google_assistant` from
  both the central monitor and the cluster-104 observer.
- Prometheus alerts now cover the new semantic HA health metrics, including a
  missing-metric alert if Home Assistant is scraped but those sensors are not
  present.

## Matter Node Map

This map was read from the live Home Assistant entity registry on cluster-104.
It makes Matter server logs such as `@1:4` or node `0x4` easier to correlate
with the room/device that the family actually sees.

| Matter node | HA entity | Room/role |
| --- | --- | --- |
| `0x1` | `light.kajplats_e26_ws_globe_1600lm` | Master Bedroom Bed left |
| `0x2` | `light.kajplats_e26_ws_globe_1600lm_2` | Living Room TV right |
| `0x3` | `light.kajplats_e26_ws_globe_1600lm_3` | Living Room Couch left |
| `0x4` | `light.kajplats_e26_ws_globe_1600lm_4` | Living Room Couch right |
| `0x5` | `light.kajplats_e26_ws_globe_1600lm_5` | Master Bedroom Bed right |
| `0x6` | `light.master_switch` | Master Bedroom wall dimmer |
| `0x7` | `light.living_room_switch` | Living Room wall dimmer |
| `0x10` | `light.kajplats_e26_ws_globe_1600lm_6` | Sebby Bedroom Sofa left |
| `0x11` | `light.kajplats_e26_ws_globe_1600lm_7` | Sebby Bedroom Sofa right |
| `0x19` | `light.kajplats_e26_ws_globe_1600lm_8` | Sebby Bedroom Standing Lamp bulb 1 |
| `0x1b` | `light.kajplats_e26_ws_globe_1600lm_9` | Sebby Bedroom Standing Lamp bulb 2 |
| `0x1c` | `light.bedroom_switch` | Sebby Bedroom wall dimmer |

## IKEA Button Monitoring Scope

The aggregate button health sensors monitor the named BILRESA devices except
the intentionally unassigned green button:

| Matter node | Battery entity | Assignment |
| --- | --- | --- |
| `0xf` | `sensor.bilresa_scroll_wheel_battery_2` | Master Bedroom Orange Button |
| `0x13` | `sensor.bilresa_scroll_wheel_battery_3` | Sebby Bedroom White Button |
| `0x12` | `sensor.bilresa_scroll_wheel_battery_4` | Stale Green Button record |
| `0x17` | `sensor.bilresa_scroll_wheel_battery_6` | Dining Room Orange Button |
| `0x18` | `sensor.bilresa_scroll_wheel_battery_7` | Living Room White Button |
| `0x1a` | `sensor.bilresa_scroll_wheel_battery_8` | Master Bedroom Green Button |

`sensor.bilresa_scroll_wheel_battery_9` is the intentionally unassigned green
button and is excluded from alerts. The unlabeled BILRESA records with no
room/user assignment are also not alerting until they are confirmed to represent
real physical buttons in use.

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
- Add deeper Matter/Thread telemetry for:
  - Matter server `peer-unresponsive` event rate by node ID. Current Matter
    logs are forwarded, but no Prometheus metric exists yet for per-node timeout
    rates.
  - OTBR neighbor links with weak RSSI or low link quality. The OTBR REST probe
    confirms the border router is alive, but an OTBR CLI/textfile exporter is
    still needed for RSSI/LQI alerting.
  - Matter node ID to HA entity/room mapping in alert annotations, once
    per-node Matter metrics exist.
  - Optional HA dashboard cards for the new Prometheus-backed health signals.
- Add GitOps backup coverage for the cluster-104 local Home Assistant config
  volume. The app-level VolSync component exists in the tier-2 app definition,
  but the live cluster-104 local PV/PVC does not currently expose a
  repo-owned ReplicationSource.
- Add script execution result metrics if HA music scripts continue to be
  fragile. The current monitoring checks whether the target players are
  available before scripts run; it does not yet turn HA service-call failures
  into per-script Prometheus counters.
