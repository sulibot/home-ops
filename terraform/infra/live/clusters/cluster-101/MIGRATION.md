# Cluster-101 Refactor Migration

## Command Mapping

- Old runtime update path:
  - `cd patch && terragrunt apply`
- New runtime update path:
  - `cd config && terragrunt apply`
  - `cd ../apply && terragrunt apply`

- Old cluster stack could traverse external artifacts dependencies.
- New cluster stack is self-contained; refresh artifacts explicitly:
  - `cd terraform/infra/live/artifacts/schematic && terragrunt apply`
  - `cd ../registry && terragrunt apply`

- Old bootstrap forcing env:
  - `TALOS_RUN_BOOTSTRAP=true`
- New bootstrap forcing env:
  - `TALOS_BOOTSTRAP_MODE=true`
- Bootstrap sequence now includes:
  - `bootstrap/` -> `cilium-bootstrap/` -> `flux/`

## Structural Changes

- Added shared context: `terraform/infra/live/clusters/_shared/context.hcl`
- Added artifact handoff files under `_shared/`
- Retired `patch/` as Terragrunt execution unit
- Added `enabled` and `talos_apply_mode` in `cluster.hcl`

## Operator Checklist

1. Refresh artifacts (schematic + registry).
2. Run `compute` if image references changed.
3. Run `config` then `apply`.
4. Confirm resolved apply mode outputs from `apply`.
