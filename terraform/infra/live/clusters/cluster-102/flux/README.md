# Flux Unit

This unit consolidates the former `flux-operator`, `flux-instance`, and
`flux-bootstrap-monitor` units into one stack while preserving internal phase order.

`../cilium-bootstrap` must complete first.

Run:

```bash
terragrunt plan
terragrunt apply
```

Bootstrap-only orchestration (capability-gate monitor + CNPG restore checks) is enabled
with:

```bash
TALOS_BOOTSTRAP_MODE=true terragrunt apply
```
