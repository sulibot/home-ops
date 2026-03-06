# Flux App Graph

This repo uses a **3-tier bootstrap model** with **capability-signal dependencies**.

## Bootstrap Flow

```text
flux-system
  -> tier-0-foundation (blocking, wait=true)
       -> tier-1-infrastructure (non-blocking, wait=false)
       -> tier-2-applications (non-blocking, wait=false)
```

- Tier 0 is the only hard bootstrap gate.
- Tier 1 and Tier 2 reconcile in parallel for faster cluster bring-up.
- Fine-grained ordering is defined per app via `dependsOn` capability signals, not via global tier serialization.

## Capability Signals

Use capability kustomizations as readiness contracts:
- `secrets-ready`
- `storage-ready`
- `ingress-ready`
- `postgres-vectorchord-ready`
- optional: `identity-ready` (if/when identity becomes a shared platform contract)

Pattern:
- Infra publishes readiness signal.
- Apps depend on signal(s) they truly need.
- Unrelated apps remain parallel.

## Labels

- Top-level tier kustomizations use `metadata.labels.tier`.
- Unit/app kustomizations use `metadata.labels.layer` (+ `component`, `critical` as needed).

This keeps queries simple while preserving functional grouping.

Examples:
- `flux get kustomizations -A --status-selector ready=false`
- `flux reconcile ks --with-source -l layer=applications`

## Linting

Run graph lint before refactors/PRs:

```bash
task flux:lint-graph
```

Checks include:
- missing graph labels
- duplicate `dependsOn` entries
- tier-2 apps accidentally depending on `tier-1-infrastructure`

## Design Rule

Prefer capability dependencies over broad tier dependencies.

Good:
- app depends on `secrets-ready` + `postgres-vectorchord-ready`

Avoid:
- app depends on entire `tier-1-infrastructure`
