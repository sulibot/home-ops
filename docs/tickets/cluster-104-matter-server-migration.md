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
- Home Assistant starts the custom Matter dimmer bridge for `Living room switch`
  from the live cluster-104 PVC-backed `/config/configuration.yaml`.
- The legacy app-template Home Assistant config still defines additional
  `Master Switch` and `Bedroom Switch` bridge entries, but that path is not the
  active cluster-104 deployment.
- Several primary control entities are online in the new Home Assistant:
  - `light.sebby_bedroom_wall_dimmer`
  - `light.living_room_wall_dimmer`
  - `light.master_bedroom_wall_dimmer`
  - `light.living_room_lights`
  - `light.master_bedroom_lights`
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
  - `light.sebby_bedroom_wall_dimmer`
  - `light.living_room_wall_dimmer`
  - `light.master_bedroom_wall_dimmer`
  - `light.living_room_lights`
  - `light.master_bedroom_lights`
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

### 2026-07-05 Stale `fdb7` address repair

After a Matter Server restart, several KAJPLATS bulbs were again unavailable in
Home Assistant even though the cluster-104 OTBR had active routes for the
`fdf1:49b9:b55e:5844::/64` Thread mesh. The affected Matter operational address
hints still pointed at stale, unrouted `fdb7:*` addresses.

The live Matter PVC address files were backed up to:

- `/data/server-1-fff1/address-backup-stale-fdb7-20260705T183445Z`

Then the address hints for peers `2`, `3`, `4`, and `5` were replaced with the
current `fdf1:49b9:b55e:5844:*` addresses from each node's stored Network
Commissioning data, and `matter-server` was restarted.

Result:

- `light.kajplats_e26_ws_globe_1600lm_2` / TV right recovered.
- `light.kajplats_e26_ws_globe_1600lm_3` / Couch left recovered.
- `light.kajplats_e26_ws_globe_1600lm_5` / Bed right recovered.
- `light.kajplats_e26_ws_globe_1600lm_4` / Couch right remained unavailable;
  OTBR did not show its extended MAC in the active router table at the time, so
  it likely needs a physical bulb or fixture power cycle before Matter can
  reconnect.

### 2026-07-05 cluster-104 endpoint recovery

After later HA testing, the Matter Server Kubernetes Service had no endpoints
even though the Deployment still desired one replica. The old Matter pod had
exited successfully and stayed in `Completed` state under the `Recreate`
Deployment, leaving Home Assistant without a live Matter websocket target.

The live recovery was:

```bash
kubectl delete pod -n matter-server --field-selector=status.phase=Succeeded
kubectl rollout status deployment/matter-server -n matter-server --timeout=240s
```

After the replacement pod started, the `matter-server` Service had both IPv4 and
IPv6 endpoints again, and Home Assistant recovered the Living Room, Master, and
Bed right Matter lights. This should be treated as an operational caveat for the
single-node host-network Matter deployment: if Matter shows unavailable globally,
check for a `Completed` Matter pod and empty Service endpoints before chasing
Thread device state.

Final retest after the endpoint recovery:

- online: Living Room switch, TV right, Couch left, Couch right, Master switch,
  Bed left, Bed right, Bedroom switch, Dining Room Lights, Desk Lamp
- still unavailable: Bedroom bulb nodes `@1:10`, `@1:11`, `@1:19`, `@1:1b`
  and Dining fan bulb nodes `@1:9`, `@1:a`, `@1:b`
- OTBR was `router` with active router neighbors, and the Matter pod and Service
  endpoints were healthy.

### 2026-07-07 BILRESA peer 24 recovery

The IKEA BILRESA buttons were paired but unavailable after the cluster-104
Matter/Thread migration because their Matter Server address hints were empty or
stale. Pressing one button proved that the radio path was alive: OTBR saw sleepy
child `7201aeaa63bd1eca` at RLOC16 `0x4802`. That hardware address mapped to
Matter peer `24` (`@1:18`, `BILRESA scroll wheel`) in the stored
Network Commissioning data.

The live repair was:

1. Enable OTBR SRP server auto mode and add it to OTBR startup:
   `ot-ctl srp server auto enable`.
2. Back up peer `24`'s address hint to:
   `/data/server-1-fff1/address-backup-peer24-current-rloc-20260707T061849Z`.
3. Seed peer `24` with the current Thread RLOC address:
   `fdf1:49b9:b55e:5844:0:ff:fe00:4802`.
4. Restart `matter-server`.

After the restart, Matter Server connected to `@1:18`, read the BILRESA
attributes, and established a subscription. This confirms the BILRESA issue is
the same class of migrated Thread operational address problem seen with the
bulbs, not a Home Assistant automation-only failure.

Remaining BILRESA peers still need a physical wake/identify pass and either
automatic rediscovery or the same temporary address-hint repair. The durable
follow-up remains replacing manual address hints with healthy OTBR/SRP/DNS-SD
rediscovery.

## Related Files

- `kubernetes/clusters/cluster-104/matter-server/`
- `kubernetes/apps/tier-2-applications/kustomization.yaml`
- `kubernetes/apps/tier-2-applications/home-assistant/app/`
- `kubernetes/clusters/cluster-104/storage/home-assistant-local-pv.yaml`
- `terraform/infra/live/baremetal/cluster-104/README.md`
