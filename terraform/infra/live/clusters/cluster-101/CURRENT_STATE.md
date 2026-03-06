# Cluster-101 Current State

## Refactor Status

- Shared context introduced at `terraform/infra/live/clusters/_shared/context.hcl`.
- Cluster stack no longer traverses external artifact dependencies.
- Runtime update path unified to `config/` then `apply/`.
- `patch/` execution stage retired (docs-only directory).
- Apply safety defaults set to Talos `staged_if_needing_reboot`.
- Bootstrap path split explicitly: `bootstrap/` -> `cilium-bootstrap/` -> `flux/`.

## Artifact Handoff

Expected catalogs:

- `terraform/infra/live/clusters/_shared/artifacts-registry.json`
- `terraform/infra/live/clusters/_shared/artifacts-schematic.json`

These are written by:

- `terraform/infra/live/artifacts/registry` (`terragrunt apply`)
- `terraform/infra/live/artifacts/schematic` (`terragrunt apply`)

## Multi-Cluster

- `cluster-101`: enabled
- `cluster-102`: scaffold present and guarded (`enabled = false`)
