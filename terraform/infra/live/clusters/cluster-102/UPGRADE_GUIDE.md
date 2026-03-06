# Cluster-102 Upgrade Guide

Cluster-102 is scaffolded and disabled by default (`cluster.hcl` -> `enabled = false`).

## Principles

- Runtime config changes use one path: `config/` then `apply/`.
- Cluster stack is decoupled from artifact stack; refresh artifacts explicitly.
- `patch/` execution is retired.

## Scenario A: Machine Config-Only Change

Examples: node labels, BGP config, DNS/NTP, sysctls.

```bash
cd terraform/infra/live/clusters/cluster-102/config
terragrunt apply

cd ../apply
terragrunt apply
```

## Scenario B: Talos Image/Schematic Change

Examples: extension list or kernel args changes.

```bash
cd terraform/infra/live/artifacts/schematic
terragrunt apply

cd ../registry
terragrunt apply

cd ../../clusters/cluster-102/config
terragrunt apply

cd ../apply
terragrunt apply
```

## Scenario C: Talos/Kubernetes Version Change

1. Update `terraform/infra/live/common/versions.hcl`.
2. Refresh `artifacts/schematic` and `artifacts/registry`.
3. Re-run `cluster-102/config` and `cluster-102/apply`.
4. Perform controlled `talosctl upgrade` rollout as required.

## Safety Checklist

- Backup etcd before major upgrades.
- Confirm artifact catalogs exist:
  - `terraform/infra/live/clusters/_shared/artifacts-schematic.json`
  - `terraform/infra/live/clusters/_shared/artifacts-registry.json`
- Verify `apply` outputs resolved apply mode per node.
