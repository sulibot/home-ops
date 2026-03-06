# Tier 2: Applications

**Bootstrap behavior**: parallel (`wait: false` at tier root)

Tier 2 should start early and gate only on required capabilities.

## Dependency Pattern

Prefer explicit capability dependencies per app:
- `secrets-ready` for secret materialization contracts
- `storage-ready` for PVC-dependent apps
- `postgres-vectorchord-ready` for DB-backed apps
- optional future `identity-ready` for SSO-hard dependencies

Avoid broad dependencies on `tier-1-infrastructure`.

## Why

- Faster overall boot: unrelated apps reconcile immediately.
- Safer startup: dependent apps wait on concrete readiness contracts.
- Easier operations: graph intent is visible per app `ks.yaml`.

## Validation

Use:

```bash
task flux:lint-graph
```

to catch dependency and label drift.
