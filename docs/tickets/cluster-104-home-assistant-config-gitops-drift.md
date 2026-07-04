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
