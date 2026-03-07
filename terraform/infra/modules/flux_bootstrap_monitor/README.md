# Flux Bootstrap Monitor Module

Bootstrap-only Flux orchestration for first cluster bring-up.

## Purpose

This module runs **only when `bootstrap_mode=true` in `flux_stack`**.
It accelerates first reconciliation and validates capability gates without changing
steady-state Flux intervals in Git.

## Flow

1. Request immediate Flux reconcile annotations.
2. Check Tier-0 and Tier-1 status snapshots.
3. Run inline CNPG recovery orchestration (declared in module `main.tf`).
4. Launch an in-cluster Job to validate bootstrap capability gates:
   - `secrets-ready`
   - `storage-ready`
   - `postgres-vectorchord-ready`
5. Trigger a final reconcile cascade.

## Inputs

- `kubeconfig_path`: kubeconfig used by local-exec actions.
- `bootstrap_timeout_seconds`: timeout budget for capability-gate checks.
- `cnpg_restore_mode`: `RESTORE_REQUIRED` (default) or `NEW_DB`.
- `cnpg_restore_method`: `auto` (default), `barman`, or `snapshot`.
- `cnpg_backup_max_age_hours`: freshness threshold for acceptable restore sources.
- `cnpg_stale_backup_max_age_minutes`: stale non-completed Backup CR cleanup threshold.
- `cnpg_storage_size`: storage size used when inline restore orchestration recreates the CNPG cluster.
- `region`: passthrough compatibility input.

## Outputs

- `tier_0_ready`: Tier-0 check status string.
- `tier_1_ready`: Tier-1 check status string.
- `bootstrap_complete`: `true` once monitor sequence completes.

## Notes

- This module is designed to run as a child of `flux_stack`, not as a standalone Terragrunt unit.
- It does not mutate Flux `interval` settings or commit changes to Git.
- In steady-state applies, keep `bootstrap_mode=false` and this module is skipped.
- Restore flow is fail-closed by default: in `RESTORE_REQUIRED`, bootstrap fails if no fresh backup source exists.
