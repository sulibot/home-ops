# Cluster-101 Workflow Guide

## Required Order

1. `secrets/` (only when explicitly regenerating)
2. `compute/`
3. `config/`
4. `apply/`
5. `bootstrap/` (one-time, auto-skips after kubeconfig/API are ready)
6. `cilium-bootstrap/` (one-time, auto-skips after kubeconfig/API are ready)
7. `flux/` (consolidated module with operator -> instance -> bootstrap-monitor sequencing)

For initial cluster build, run with bootstrap mode enabled:

```bash
TALOS_BOOTSTRAP_MODE=true terragrunt apply --all --non-interactive
```

For steady-state run-all, omit bootstrap mode:

```bash
terragrunt apply --all --non-interactive
```

## Runtime Machine Config Updates

Single supported path:

```bash
cd config && terragrunt apply
cd ../apply && terragrunt apply
```

Do not use `patch/`; it is retired.

## Artifact Refresh Boundary

Cluster stack is decoupled from `live/artifacts/*` traversal.

Refresh artifacts explicitly before cluster operations that depend on new image/schematic data:

```bash
cd terraform/infra/live/artifacts/schematic && terragrunt apply
cd ../registry && terragrunt apply
```

These commands update shared handoff catalogs in `terraform/infra/live/clusters/_shared/`.

## Common Scenarios

### 1) Node labels, BGP tuning, network/sysctls

```bash
cd config && terragrunt apply
cd ../apply && terragrunt apply
```

### 2) Talos/system extension updates

```bash
cd terraform/infra/live/artifacts/schematic && terragrunt apply
cd ../registry && terragrunt apply

cd ../../clusters/cluster-101/config && terragrunt apply
cd ../apply && terragrunt apply
```

For installed Talos binary updates, continue to use `talosctl upgrade` where appropriate.

### 3) Kubernetes/Talos version updates

Update `common/versions.hcl`, refresh artifact catalogs, regenerate config, apply, then perform controlled node upgrades.

## Cluster-102 Scaffold

`cluster-102` mirrors this structure but is guarded by default (`enabled = false`).
Enable intentionally in `cluster-102/cluster.hcl` before use.
