# Flux Bootstrap Monitor Module

Bootstrap-only Flux orchestration for first cluster bring-up.

## Purpose

This module runs **only when `bootstrap_mode=true` in `flux_stack`**.
It accelerates first reconciliation and validates capability gates without changing
steady-state Flux intervals in Git.

## Flow

1. Request immediate Flux reconcile annotations.
2. Check Tier-0 and Tier-1 status snapshots.
3. Run CNPG recovery helper (`scripts/cnpg-restore.sh`).
4. Launch an in-cluster Job to validate bootstrap capability gates:
   - `secrets-ready`
   - `storage-ready`
   - `postgres-vectorchord-ready`
5. Trigger a final reconcile cascade.

## Inputs

- `kubeconfig_path`: kubeconfig used by local-exec actions.
- `bootstrap_timeout_seconds`: timeout budget for capability-gate checks.
- `region`: passthrough compatibility input.

## Outputs

- `tier_0_ready`: Tier-0 check status string.
- `tier_1_ready`: Tier-1 check status string.
- `bootstrap_complete`: `true` once monitor sequence completes.

## Notes

- This module is designed to run as a child of `flux_stack`, not as a standalone Terragrunt unit.
- It does not mutate Flux `interval` settings or commit changes to Git.
- In steady-state applies, keep `bootstrap_mode=false` and this module is skipped.
