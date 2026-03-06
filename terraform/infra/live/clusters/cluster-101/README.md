# Cluster-101 Deployment

Production Talos Linux Kubernetes cluster with DRY shared context and a single safe runtime apply path.

## Cluster Information

- Name: `sol`
- ID: `101`
- Control planes: `3`
- Workers: `3`
- Talos apply mode default: `staged_if_needing_reboot`

## Structure

```text
cluster-101/
├── cluster.hcl              # Cluster intent (enabled/id/name/counts/overrides)
├── secrets/                 # Talos machine secrets (normally skipped unless explicitly requested)
├── compute/                 # Proxmox VM lifecycle
├── config/                  # Talos machine config generation
├── apply/                   # Single runtime config apply path (safe default mode)
├── bootstrap/               # One-time cluster bootstrap
├── cilium-bootstrap/        # One-time Cilium/Gateway bootstrap unit
├── flux/                    # Consolidated Flux phase orchestration
├── flux-operator/           # retired (docs only)
├── flux-instance/           # retired (docs only)
└── flux-bootstrap-monitor/  # retired (docs only)
```

Shared cluster context and artifact handoff live in:

- `terraform/infra/live/clusters/_shared/context.hcl`
- `terraform/infra/live/clusters/_shared/artifacts-registry.json`
- `terraform/infra/live/clusters/_shared/artifacts-schematic.json`

## Stack Boundaries

Cluster stacks no longer traverse external `live/artifacts/*` dependencies during `run-all`.

Refresh artifacts explicitly first:

```bash
cd terraform/infra/live/artifacts/schematic
terragrunt apply

cd ../registry
terragrunt apply
```

Then run cluster stack:

```bash
cd ../../clusters/cluster-101
terragrunt apply --all --non-interactive
```

## Runtime Updates (Single Path)

Use only this path for machine config changes:

```bash
cd config
terragrunt apply

cd ../apply
terragrunt apply
```

`apply/` uses Talos provider apply mode `staged_if_needing_reboot` by default and outputs resolved apply modes per node.

## Bootstrap Safety

`bootstrap/` auto-skips when `talos/clusters/cluster-101/kubeconfig` already exists.
`cilium-bootstrap/` also auto-skips when API is already ready.

To force full bootstrap path intentionally:

```bash
TALOS_BOOTSTRAP_MODE=true terragrunt apply --all --non-interactive
```

Steady-state applies should run without bootstrap mode:

```bash
terragrunt apply --all --non-interactive
```

## Notes

- `flux/` now orchestrates operator, instance sync, and bootstrap monitor in one unit.
- Bootstrap sequence is `bootstrap/` -> `cilium-bootstrap/` -> `flux/`.
- `patch/` execution is retired; see `patch/README.md`.
- Cluster-102 scaffold exists under `terraform/infra/live/clusters/cluster-102` and is guarded by default (`enabled = false`).
