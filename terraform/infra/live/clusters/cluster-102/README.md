# Cluster-102 Scaffold

Tenant-102 Talos/Kubernetes stack scaffold.

## Guardrail

This cluster is intentionally disabled by default.

- `terraform/infra/live/clusters/cluster-102/cluster.hcl`
  - `enabled = false`

All units honor this guard via `skip = !enabled`.

## Activation

1. Set `enabled = true` in `cluster.hcl`.
2. Confirm cluster identity/network values (`cluster_name`, `tenant_id`, `vnet`; keep `cluster_id` alias aligned).
3. Refresh artifact catalogs:
   - `terraform/infra/live/artifacts/schematic`
   - `terraform/infra/live/artifacts/registry`
4. Run standard order:
   - `secrets` -> `compute` -> `config` -> `apply` -> `bootstrap` -> `cilium-bootstrap` -> `flux`

For first build, force bootstrap-mode units:

```bash
TALOS_BOOTSTRAP_MODE=true terragrunt apply --all --non-interactive
```

## Notes

- `flux/` now orchestrates operator, instance sync, and bootstrap monitor in one unit.
- Bootstrap sequence is `bootstrap/` -> `cilium-bootstrap/` -> `flux/`.
- Runtime updates use only `config/` then `apply/`.
- `patch/` execution path is retired.
