# Shared Talos Artifacts

This stack publishes Talos artifacts shared by all tenant clusters.

## Current Flow (No Docker)

```text
artifacts/schematic  -> writes artifacts-schematic.json
artifacts/registry   -> downloads Talos ISO from factory.talos.dev directly to Proxmox datastore
                      -> writes artifacts-registry.json
```

There is no required local ISO build and no SCP in the normal workflow.

## Stacks

- `schematic/`: Generates Talos Image Factory schematic ID from `common/install-schematic.hcl`.
- `registry/`: Uses `modules/talos_proxmox_image` and `proxmox_virtual_environment_file` to let Proxmox download the ISO from URL.

## Outputs / Handoff Catalogs

Written under `terraform/infra/live/clusters/_shared/`:
- `artifacts-schematic.json`
- `artifacts-registry.json`

Cluster stacks read these catalogs and do not traverse `live/artifacts/*` dependencies during cluster `run-all`.

## Usage

```bash
cd terraform/infra/live/artifacts/schematic
terragrunt apply

cd ../registry
terragrunt apply
```

Then deploy cluster stack.

## Notes

- `images/` is legacy/deprecated and Docker-based; it is not part of the default path.
- Registry apply requires valid Proxmox provider environment/credentials.
