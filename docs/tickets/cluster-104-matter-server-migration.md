# Ticket: Move Matter server control plane to cluster-104

- Status: Open
- Priority: High
- Area: cluster-104 Home Assistant, Matter, Thread
- Created: 2026-07-03

## Summary

Home Assistant now runs on `cluster-104`, but the Matter server that owns the
existing Matter fabric still runs on the main cluster. To restore immediate
control, the migrated Home Assistant instance was repointed from the old
cluster-local service URL to the routable Gateway URL:

- From: `ws://matter-server.matter-server.svc.cluster.local:5580/ws`
- To: `wss://matter-server.sulibot.com/ws`

This gives the new Home Assistant process access to the existing Matter server
without re-pairing devices or changing the Matter fabric.

## Current State

- `cluster-104` Home Assistant is running and connected to the existing Matter
  server over WebSocket.
- The Matter server reports the Home Assistant websocket connection and returns
  the existing Matter node set.
- Home Assistant starts the custom Matter dimmer bridge for:
  - `Living room switch`
  - `Master Switch`
  - `Bedroom Switch`
- Several primary control entities are online in the new Home Assistant:
  - `light.bedroom_switch`
  - `light.living_room_switch`
  - `light.master_switch`
  - `light.living_room_lights`
  - `light.master_lights`
- Many individual Matter bulb/button entities still report `unavailable`.

## Why This Is Not Final

The current routing is operational, but the ownership is awkward:

- Home Assistant is on `cluster-104`.
- Matter server is still on the main cluster.
- The Matter server data PVC and Matter fabric state still live on the main
  cluster storage.
- The old cluster therefore remains in the Home Assistant control path.

This is acceptable as a temporary recovery/control bridge, but the intended
final state is to move the Matter server and its data to `cluster-104`.

## Acceptance Criteria

- Matter server runs on `cluster-104`.
- Matter server persistent data is migrated or restored on `cluster-104`
  without losing the Matter fabric.
- Home Assistant Matter integration points back to a cluster-local endpoint:
  `ws://matter-server.matter-server.svc.cluster.local:5580/ws`.
- The old/main cluster is no longer required for Home Assistant Matter control.
- The main Matter-controlled switches and groups remain online after migration:
  - `light.bedroom_switch`
  - `light.living_room_switch`
  - `light.master_switch`
  - `light.living_room_lights`
  - `light.master_lights`
- Remaining unavailable Matter bulbs are triaged as either:
  - actually offline/powered/unreachable devices, or
  - Matter/Thread routing issues.

## Related Files

- `kubernetes/apps/tier-2-applications/matter-server/`
- `kubernetes/clusters/cluster-104/home-assistant/`
- `terraform/infra/live/baremetal/cluster-104/README.md`
