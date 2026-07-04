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

## Problem

The older app-template Home Assistant config under
`kubernetes/apps/tier-2-applications/home-assistant/app/` still records much of
the desired YAML intent, but that path is not the active deployment for
cluster-104. The active deployment is:

- `kubernetes/clusters/cluster-104/home-assistant/deployment.yaml`
- PVC: `home-assistant-config`
- mount: `/config`

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

- `kubernetes/clusters/cluster-104/home-assistant/deployment.yaml`
- `kubernetes/clusters/cluster-104/storage/home-assistant-local-pv.yaml`
- `docs/runbooks/home-assistant-operations.md`
- `kubernetes/apps/tier-2-applications/home-assistant/app/`
