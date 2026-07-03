# Ticket: Move Matter server control plane to cluster-104

- Status: Done
- Priority: High
- Area: cluster-104 Home Assistant, Matter, Thread
- Created: 2026-07-03

## Summary

Home Assistant and the Matter server now both run on `cluster-104`. The existing
Matter fabric data was copied from the old/main cluster and restored into the
cluster-104 local Matter PVC without re-pairing devices.

## Current State

- `cluster-104` Home Assistant is running and connected to the cluster-local
  Matter service:
  `ws://matter-server.matter-server.svc.cluster.local:5580/ws`.
- The cluster-104 Matter server reports the Home Assistant websocket connection
  and returns 27 Matter nodes.
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

## Migration Result

- Old/main cluster `matter-server` deployment was scaled to `0`.
- Active Matter data was archived from the stopped old PVC and restored to the
  cluster-104 local PVC.
- New Matter server runs as a host-network workload on `talos01` with
  `--primary-interface=enp1s0.31`.
- `talos01[ether5]` carries tagged `vlan31` for Matter/IoT traffic in addition
  to native recovery `vlan10` and tagged cluster `vlan104`.
- Home Assistant now points to the cluster-local Matter service.

## Acceptance Criteria

- [x] Matter server runs on `cluster-104`.
- [x] Matter server persistent data is migrated or restored on `cluster-104`
  without losing the Matter fabric.
- [x] Home Assistant Matter integration points back to a cluster-local endpoint:
  `ws://matter-server.matter-server.svc.cluster.local:5580/ws`.
- [x] The old/main cluster is no longer required for Home Assistant Matter control.
- [x] The main Matter-controlled switches and groups remain online after migration:
  - `light.bedroom_switch`
  - `light.living_room_switch`
  - `light.master_switch`
  - `light.living_room_lights`
  - `light.master_lights`
- [ ] Remaining unavailable Matter bulbs are triaged as either:
  - actually offline/powered/unreachable devices, or
  - Matter/Thread routing issues.

## Related Files

- `kubernetes/clusters/cluster-104/matter-server/`
- `kubernetes/apps/tier-2-applications/kustomization.yaml`
- `kubernetes/clusters/cluster-104/home-assistant/`
- `terraform/infra/live/baremetal/cluster-104/README.md`
