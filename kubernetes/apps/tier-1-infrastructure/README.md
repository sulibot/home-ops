# Tier 1: Infrastructure

**Bootstrap behavior**: parallel (`wait: false` at tier root)

Tier 1 provides shared platform capabilities consumed by tier-2 apps.

## Responsibilities

- Core platform services (cert-manager, coredns, metrics, etc.)
- Network services (gateway, DNS automation, tunnels)
- Data services (CNPG, backups)
- Capability readiness signals for app ordering

## Capability Signals Published

- `secrets-ready`
- `storage-ready`
- `ingress-ready`
- `postgres-vectorchord-ready`

These signals are the preferred contract for tier-2 app dependencies.

## Ordering Model

- Do not force tier-2 to wait on all tier-1.
- Publish readiness from infra units.
- Let apps depend only on capabilities they require.

This keeps bootstrap fast while preserving safe ordering.
