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
- Thread bulb control was restored after clearing stale migrated address hints
  and seeding the Matter server cache with each KAJPLATS bulb's stable Thread
  mesh-local `fdf1:49b9:b55e:5844:*` address.
- Living Room KAJPLATS nodes were validated after migration:
  - `@1:2` / `TV right` is online.
  - `@1:3` / `Couch left` required adding its live Thread RLOC hint
    `fdf1:49b9:b55e:5844:0:ff:fe00:a400` before it reconnected.
  - `@1:4` / `Couch right` is online.
- The underlying follow-up is still open: OTBR/SRP/DNS-SD should refresh Thread
  operational addresses automatically after a border-router / cluster migration,
  instead of depending on manually seeded mesh-local Matter address hints.

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
- [x] Remaining unavailable Matter bulbs are triaged as a Matter/Thread address
  rediscovery issue after the cluster-104 migration.
- [x] Stale migrated KAJPLATS address hints were backed up under the Matter PVC:
  `/data/server-1-fff1/address-backup-20260703222222`.
- [x] KAJPLATS bulbs were given mesh-local Matter address hints from their
  stored Thread Network Commissioning data.
- [ ] Replace the mesh-local address seeding workaround with healthy
  OTBR/SRP/DNS-SD rediscovery.

## Follow-up: Thread Address Rediscovery

During the migration, the Matter server retained stale Thread operational
addresses for the KAJPLATS bulbs. The stale addresses pointed at old Thread OMR
or old infrastructure prefixes such as `fdb7:*`, `fdac:*`, and
`2600:1700:ab1a:500b:*`, while the new cluster-104 OTBR advertises
`fd09:7aa3:6ab9::/64` on the `vlan31` infrastructure network.

The immediate repair was:

1. Back up and remove stale `nodes.peer*.endpoints.0.commissioning.addresses`
   files for the KAJPLATS bulb peers.
2. Seed replacement address hints using the bulbs' stored Thread mesh-local
   `fdf1:49b9:b55e:5844:*` addresses.
3. Add the live Thread RLOC for any bulb that had rejoined Thread as a router
   but was still not being reached by Matter, for example `@1:3` /
   `Couch left` at `fdf1:49b9:b55e:5844:0:ff:fe00:a400`.
4. Restart `matter-server`.

That restored Thread sessions and subscriptions for responding KAJPLATS nodes,
but it is intentionally treated as operational debt. The durable fix should make
the new OTBR and Matter server rediscover current Thread operational addresses
without hand-maintained cache entries.

## Related Files

- `kubernetes/clusters/cluster-104/matter-server/`
- `kubernetes/apps/tier-2-applications/kustomization.yaml`
- `kubernetes/clusters/cluster-104/home-assistant/`
- `terraform/infra/live/baremetal/cluster-104/README.md`
