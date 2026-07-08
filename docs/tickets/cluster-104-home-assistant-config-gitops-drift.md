# Ticket: Bring cluster-104 Home Assistant runtime config under Git intent

- Status: Open
- Priority: Medium
- Area: cluster-104 Home Assistant, GitOps, restore/rebuild
- Created: 2026-07-03

## Summary

`cluster-104` Home Assistant runs from the local `home-assistant-config` PVC.
That PVC contains `/config/configuration.yaml`, `/config/automations.yaml`,
custom components, entity registry state, Matter integration state, and UI
state. The active Kubernetes manifests for `cluster-104` mount the PVC directly
and do not currently project the Home Assistant YAML from Git.

This is acceptable for the immediate bare-metal cutover, but it means runtime
configuration fixes can drift from the repository unless they are also
documented or translated into a Git-managed pattern.

## Current Live Fix

On `2026-07-03`, the live `/config/configuration.yaml` on cluster-104 was
updated to make the Living Room control semantics explicit:

- `light.living_room_lights` groups:
  - `light.kajplats_e26_ws_globe_1600lm_2` (`TV right`)
  - `light.kajplats_e26_ws_globe_1600lm_3` (`Couch left`)
  - `light.kajplats_e26_ws_globe_1600lm_4` (`Couch right`)
- `light.couch` groups:
  - `light.kajplats_e26_ws_globe_1600lm_3` (`Couch left`)
  - `light.kajplats_e26_ws_globe_1600lm_4` (`Couch right`)
- `matter_dimmer_bridge` maps the Matter `Living room switch` (`node_id: 7`,
  `light.living_room_switch`) to `light.living_room_lights`.

Home Assistant's config check passed and the deployment was restarted. Startup
logs confirmed:

```text
Started Matter dimmer bridge for Living room switch
```

The migration also left a stale entity-registry entry where
`light.living_room_lights` pointed at the old template light. After adding the
real YAML light group, Home Assistant initially created it as
`light.living_room_lights_2`. The registry was corrected while Home Assistant
was stopped:

- backed up `/config/.storage/core.entity_registry`
- removed the stale template `light.living_room_lights` entry
- renamed the group `light.living_room_lights_2` entry back to
  `light.living_room_lights`

After restart, the live registry showed:

```text
light.living_room_lights platform=group unique_id=living_room_lights_group
light.couch platform=group unique_id=couch_group
```

On `2026-07-03`, the live `/config/configuration.yaml` was also updated for
Master and Bedroom:

- `matter_dimmer_bridge` starts for:
  - `Living room switch`
  - `Master Switch`
  - `Bedroom Switch`
- `light.master_lights` groups:
  - `light.kajplats_e26_ws_globe_1600lm`
  - `light.kajplats_e26_ws_globe_1600lm_5`
- `light.sofa` groups:
  - `light.kajplats_e26_ws_globe_1600lm_6`
  - `light.kajplats_e26_ws_globe_1600lm_7`
- `light.standing_lamp` groups:
  - `light.kajplats_e26_ws_globe_1600lm_8`
  - `light.kajplats_e26_ws_globe_1600lm_9`
- `light.bedroom_lights` groups:
  - `light.sofa`
  - `light.standing_lamp`

The stale template `light.master_lights` registry entry was removed while Home
Assistant was stopped so the Git/YAML group could own the intended entity id.
Backups were left on the PVC:

- `/config/configuration.yaml.bak-codex-20260704T062604Z`
- `/config/.storage/core.entity_registry.bak-codex-master-bedroom-20260704T062727Z`

After restart, the live registry showed:

```text
light.master_lights platform=group unique_id=master_lights_group
light.sofa platform=group unique_id=sofa_group
light.standing_lamp platform=group unique_id=standing_lamp_group
light.bedroom_lights platform=group unique_id=bedroom_lights_group
```

Master lights were online after this cleanup. Bedroom groups were correctly
defined, but remained unavailable because all four underlying Bedroom Matter
bulbs were unavailable:

- `light.kajplats_e26_ws_globe_1600lm_6`
- `light.kajplats_e26_ws_globe_1600lm_7`
- `light.kajplats_e26_ws_globe_1600lm_8`
- `light.kajplats_e26_ws_globe_1600lm_9`

The Bedroom switch itself was online and on:

```text
light.bedroom_switch on
number.bedroom_switch_on_level 255
```

Matter address hints were backed up and updated for Bedroom bulb nodes
`16`, `17`, `25`, and `27`:

- backup: `/data/server-1-fff1/address-backup-bedroom-20260704T062954Z`
- added cached Thread RLOC hints alongside the mesh-local EID hints

Matter Server was restarted after the address update. It initialized the
Bedroom bulb nodes (`@1:10`, `@1:11`, `@1:19`, `@1:1b`) and attempted to connect
to the new RLOC hints, but Home Assistant still reported the bulbs unavailable.
A temporary host-network debug pod on `talos01` verified that known-good
Living/Master Thread bulb addresses responded to ping, while the Bedroom bulb
cached addresses did not.

Remaining Bedroom issue: the Home Assistant YAML and entity ids are now aligned,
but the Bedroom KAJPLATS bulbs are still not reachable on Thread/Matter from
`talos01`. The likely next operational step is to physically power-cycle the
Bedroom bulbs / fixture circuit so the bulbs rejoin Thread, then restart
`matter-server` if Home Assistant does not automatically recover them.

On `2026-07-05`, the live cluster-104 PVC-backed
`/config/configuration.yaml` was checked again after the Home Assistant cutover.
The `Bedroom Lights` group still referenced stale `light.essentials_a19_a60_6`
and `light.essentials_a19_a60_7` entities even though the active switch bridge
and Matter registry use:

- `light.kajplats_e26_ws_globe_1600lm_6` / Matter `@1:10` / `Sofa_left`
- `light.kajplats_e26_ws_globe_1600lm_7` / Matter `@1:11` / `Sofa_right`

The live PVC config and the repo template were updated so `Bedroom Lights`
now groups the current Sofa bulbs plus `light.standing_lamp`. Home Assistant
config check passed and the deployment was restarted. After restart:

- Living Room switch and bulbs were online.
- Master switch, Bed left, and Bed right were online.
- `light.bedroom_switch` was online.
- `light.bedroom_lights`, `light.sofa`, `light.standing_lamp`, and bedroom
  bulb nodes `@1:10`, `@1:11`, `@1:19`, and `@1:1b` remained unavailable.
- `light.dining_room_lights` was online because `light.desk_lamp` was online.
- `light.dining_room_fan` and fan bulb nodes `@1:9`, `@1:a`, and `@1:b`
  remained unavailable.

Matter Server, its Kubernetes Service endpoints, and OTBR were healthy at the
time, so the remaining bedroom/fan issue is tracked as per-device Matter/Thread
reachability rather than a global cluster-104 or Home Assistant config failure.

On `2026-07-04`, the live custom component
`/config/custom_components/matter_dimmer_bridge/__init__.py` was patched on the
PVC after a `matter-server` restart left Home Assistant subscribed to stale
Matter client callbacks. The patch adds a watchdog that checks the active Home
Assistant Matter client and rebinds dimmer subscriptions if the client changes.
A backup was left on the PVC:

- `/config/custom_components/matter_dimmer_bridge/__init__.py.backup-20260704T070603Z`

Home Assistant was restarted after the patch and startup logs confirmed:

```text
Started Matter dimmer bridge for Living room switch, Master Switch, Bedroom Switch
```

Current validation after the restart:

- HA direct VLAN access works on `http://10.30.0.251:8123/` and
  `http://10.31.0.251:8123/`.
- `light.master_switch`, `light.master_lights`, and both Master bulbs are
  available and on.
- `light.bedroom_switch` is available and on.
- `light.bedroom_lights`, `light.sofa`, `light.standing_lamp`, and Bedroom
  bulbs `0x10`, `0x11`, `0x19`, and `0x1b` are still unavailable in Home
  Assistant.
- Matter Server sees the Bedroom switch (`@1:1c`) on VLAN31 and keeps receiving
  its subscription reports. The Bedroom bulb nodes are still failing Matter
  reachability with stale/no Thread addresses, so this remains a device
  reachability problem rather than a Home Assistant group mapping problem.

On `2026-07-06`, Bedroom was checked again after the physical lights were
reported on but unavailable in Home Assistant. Current state:

- `light.bedroom_switch` is available and on.
- `light.bedroom_lights`, `light.sofa`, `light.standing_lamp`, and the four
  Bedroom KAJPLATS bulbs are unavailable in Home Assistant.
- Matter Server still knows the bulb nodes (`@1:10`, `@1:11`, `@1:19`,
  `@1:1b`), but all four were unavailable and failed reads with `Operation
  aborted`.
- The cached address hints for peers `16`, `17`, `25`, and `27` still pointed
  at stale `fdb7:*` Thread addresses. They were backed up to
  `/data/server-1-fff1/address-backup-bedroom-stale-fdb7-20260707T002047Z`
  and removed.
- After restarting `matter-server`, the stale address hints stayed removed, but
  Matter Server still reported `Resolving (no address known)` for the Bedroom
  bulb nodes and did not rediscover fresh addresses.
- OTBR remained healthy as a router on the current Thread network, with extended
  PAN ID `c0d45ec1c7111ca2`, PAN ID `0xbd99`, channel `20`, mesh-local prefix
  `fdf1:49b9:b55e:5844::/64`, and infrastructure prefix
  `fd09:7aa3:6ab9:0::/64`.

Remaining Bedroom issue: the bulbs are electrically on, but not discoverable to
the Matter fabric. The next operational step is to physically power-cycle the
Bedroom bulbs / fixture circuit so the bulbs reboot and re-advertise on Thread,
then re-check Matter Server. If they still do not appear with fresh addresses,
the next repair is to re-pair those four Bedroom bulbs rather than editing Home
Assistant group config.

After the Bedroom bulbs were physically restarted, Matter Server was still not
able to rediscover the nodes with no cached addresses. The prior known-good
`fdf1:49b9:b55e:5844:*` mesh-local address hints from
`/data/server-1-fff1/address-backup-bedroom-20260704T062954Z` were reseeded
for peers `16`, `17`, `25`, and `27`, with a pre-change backup at
`/data/server-1-fff1/address-backup-bedroom-reseed-before-20260707T003857Z`.
After restarting `matter-server`, direct Matter reads succeeded:

```text
@1:10 on=True level=42
@1:11 on=True level=191
@1:19 on=True level=203
@1:1b on=True level=203
```

Home Assistant then showed all Bedroom entities online/on:

```text
light.bedroom_lights on
light.sofa on
light.standing_lamp on
light.kajplats_e26_ws_globe_1600lm_6 on
light.kajplats_e26_ws_globe_1600lm_7 on
light.kajplats_e26_ws_globe_1600lm_8 on
light.kajplats_e26_ws_globe_1600lm_9 on
```

On `2026-07-04`, Dining Room was reviewed with the same process. The underlying
Dining devices were healthy:

- `light.fan_1`
- `light.fan_2`
- `light.fan_3`
- `light.desk_lamp`

The stale Dining group entities existed in the entity registry, but the active
PVC `/config/configuration.yaml` no longer defined them, so Home Assistant
reported `light.dining_room_lights` and `light.dining_room_fan` as unavailable.
The live PVC config was updated to restore:

- `light.dining_room_fan`, grouping `light.fan_1`, `light.fan_2`, and
  `light.fan_3`
- `light.dining_room_lights`, grouping the three fan lights plus
  `light.desk_lamp`
- `button.dining_room_button`, a template button that toggles
  `light.dining_room_lights`

A backup was left on the PVC:

- `/config/configuration.yaml.bak-codex-dining-20260704T071535Z`

Home Assistant config check passed, the deployment was restarted, and validation
after restart showed:

```text
light.dining_room_lights on
light.dining_room_fan on
light.desk_lamp on
light.fan_1 on
light.fan_2 on
light.fan_3 on
```

The old Bilresa Dining automations still exist as stale registry entries but
live `/config/automations.yaml` is currently empty. Reintroducing those
automations should be handled deliberately as a separate migration step rather
than by blindly restoring the legacy automation file.

On `2026-07-05`, the live `/config/configuration.yaml` was missing the
top-level `auth_oidc:` block even though `/config/custom_components/auth_oidc`
was present. The HA login page therefore only offered `Trusted Networks` and
`Home Assistant Local`, and `/auth/oidc/redirect` was not available as the
expected SSO path.

The live PVC config was backed up and patched:

- backup: `/config/configuration.yaml.bak-before-oidc-auth-20260706T000904Z`
- restored `auth_oidc` with the Authentik discovery URL:
  `https://auth.sulibot.com/application/o/home-assistant-app/.well-known/openid-configuration`
- installed the missing `joserfc==1.6.3` dependency into `/config/.venv`
- Home Assistant config check passed and the deployment was restarted

Validation after restart:

```json
{
  "providers": [
    {"name": "Authentik SSO", "type": "auth_oidc"},
    {"name": "Trusted Networks", "type": "trusted_networks"},
    {"name": "Home Assistant Local", "type": "homeassistant"}
  ]
}
```

`/auth/oidc/redirect` now returns a `302` to Authentik with
`client_id=homeassistant-app`.

On `2026-07-07`, Home Assistant room-switch and IKEA BILRESA button behavior
was reviewed after Matter Server / Thread migration work.

Changes applied:

- `matter_dimmer_bridge` now watches for a replaced Matter client and rebinds
  subscriptions after Matter Server restarts.
- The watcher is started with `hass.async_create_background_task(...)` so it no
  longer blocks Home Assistant startup completion.
- Template light transition values were changed from string/`none` rendering to
  a numeric default:
  `{{ transition | default(0, true) | float }}`.

Live validation:

- Home Assistant restarted cleanly.
- The bridge logged:
  `Started Matter dimmer bridge for Living room switch, Master Switch, Bedroom Switch`.
- After a Matter Server restart, the bridge logged:
  `Matter dimmer bridge rebinding to new Matter client`.
- Matter nodes for the room switches are online:
  - `6`: Master Switch
  - `7`: Living room switch
  - `28`: Bedroom Switch

Remaining IKEA / Matter device issue:

- IKEA BILRESA button nodes are paired and their Matter endpoints load, but they
  remain unavailable until they wake and resolve on the current Thread network.
- Current BILRESA Matter nodes:
  `14`, `15`, `18`, `19`, `20`, `23`, `24`, `26`, `29`.
- Their stale address hints were backed up and cleared:
  `/data/server-1-fff1/address-backup-bilresa-reseed-before-20260707T050850Z`.
- After pressing one IKEA BILRESA, OTBR showed sleepy child
  `7201aeaa63bd1eca` at RLOC16 `0x4802`, which mapped to Matter peer `24`
  / `@1:18` / `BILRESA scroll wheel`.
- Peer `24` was repaired by backing up its empty address hint and seeding the
  current Thread RLOC address:
  `/data/server-1-fff1/address-backup-peer24-current-rloc-20260707T061849Z`
  and `fdf1:49b9:b55e:5844:0:ff:fe00:4802`.
- After restarting Matter Server, peer `24` connected and established a
  subscription. Other BILRESA nodes still need the same wake/identify/reseed
  flow or re-pairing if they do not expose a current Thread address.
- The Home Assistant entity registry had BILRESA
  `sensor.bilresa_scroll_wheel_current_switch_position*` entities disabled by
  the Matter integration, while the BILRESA automation blueprint depends on
  those sensors for wheel/scroll dimming. The registry was backed up to
  `/config/.storage/core.entity_registry.bak-bilresa-enable-switch-position-20260707T062653Z`,
  the BILRESA switch-position sensors were enabled, and Home Assistant was
  restarted. A post-restart registry check showed `0` disabled BILRESA
  switch-position sensors.

Remaining Bed right / Master target issue:

- Matter node `5` remains unavailable and is the likely source of `Bed right`
  / `light.kajplats_e26_ws_globe_1600lm_5` operation failures.
- Its address hint was backed up and cleared:
  `/data/server-1-fff1/address-backup-peer5-reseed-before-20260707T051257Z`.
- It is now also waiting on Matter rediscovery as
  `Resolving (no address known)`.

## Problem

The Home Assistant workload is owned by the shared app HelmRelease under
`kubernetes/apps/tier-2-applications/home-assistant/app/`, while cluster-104 owns
the local persistence and routing. The active cluster-104 state is:

- workload: `kubernetes/apps/tier-2-applications/home-assistant/app/`
- PVC: `home-assistant-config`
- mount: `/config`
- cluster-local storage/routes:
  `kubernetes/clusters/cluster-104/storage/home-assistant-local-pv.yaml` and
  `kubernetes/clusters/cluster-104/network/home-assistant-routes.yaml`

As a result, a future rebuild or restore can lose live YAML changes unless the
PVC backup is restored exactly or the desired runtime config is codified for
cluster-104.

## Impact

- Button, group, and custom integration behavior can differ between Git and the
  live Home Assistant instance.
- A fresh `cluster-104` deployment from only Kubernetes manifests will not
  recreate the Home Assistant YAML behavior.
- Troubleshooting is harder because the old app-template path looks authoritative
  but is not currently applied to cluster-104.

## Acceptance Criteria

- Decide the long-term ownership model for Home Assistant YAML on cluster-104:
  - keep `/config` fully stateful and document all live edits in tickets/runbooks,
    or
  - project selected Git-managed YAML files into `/config`, or
  - add a safe init/sync job that seeds/updates selected YAML without overwriting
    user-managed `.storage` state.
- The active cluster-104 path clearly documents where Home Assistant YAML intent
  lives.
- Living Room controls remain reproducible:
  - wall switch controls `light.living_room_lights`
  - `light.couch` controls only couch-left and couch-right
- The old app-template path is either retired for Home Assistant or explicitly
  marked as legacy/not active for cluster-104.
- Restore/rebuild documentation explains whether the PVC backup or Git is the
  source of truth for `/config/configuration.yaml`.

## Related Files

- `kubernetes/apps/tier-2-applications/home-assistant/app/`
- `kubernetes/clusters/cluster-104/storage/home-assistant-local-pv.yaml`
- `kubernetes/clusters/cluster-104/network/home-assistant-routes.yaml`
- `docs/runbooks/home-assistant-operations.md`
