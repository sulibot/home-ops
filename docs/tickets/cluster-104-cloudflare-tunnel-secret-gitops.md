---
title: Move cluster-104 Cloudflare tunnel credentials under GitOps secret management
status: resolved
created: 2026-07-04
resolved: 2026-07-04
cluster: cluster-104
area: cloudflare
---

## Summary

`cluster-104` now runs its own Cloudflare Tunnel for Home Assistant external
WARP access. The tunnel credentials are managed by External Secrets from the
`cloudflare` 1Password item and rendered to a Kubernetes Secret named
`cloudflare-tunnel-secret` in the `network` namespace.

This is now GitOps-recoverable after the normal cluster bootstrap requirement:
Flux must have the `sops-age` secret so it can decrypt the 1Password Connect
credentials manifest.

## Current State

- Cloudflare tunnel name: `cluster-104`
- Cloudflare tunnel ID is stored in SOPS Terraform secrets as
  `cloudflare_tunnel_id_cluster_104`
- 1Password item: `cloudflare`
- 1Password fields:
  - `CLOUDFLARE_TUNNEL_ID_CLUSTER_104`
  - `CLOUDFLARE_TUNNEL_SECRET_CLUSTER_104`
- Public DNS for `hass.sulibot.com` points to the cluster-104 tunnel
- `hass-app.sulibot.com` is intentionally internal/WARP-private only and should
  not be published through Cloudflare Access
- Kubernetes deployment:
  - `kubernetes/clusters/cluster-104/cloudflare-tunnel/`
- Generated credential Secret:
  - namespace: `network`
  - name: `cloudflare-tunnel-secret`
  - keys: `credentials.json`, `config.yaml`

## Resolution

Cluster-104 now mirrors the cluster-101 External Secrets pattern:

- `kubernetes/clusters/cluster-104/kustomization.yaml` includes
  `../../apps/tier-0-foundation/external-secrets`
- `kubernetes/clusters/cluster-104/cloudflare-tunnel/externalsecret.yaml`
  renders the Cloudflare tunnel `credentials.json` and `config.yaml`
- `cloudflare-tunnel-secret` is owned by `ExternalSecret/cloudflare-tunnel`
- `cloudflared` routes only cluster-104-owned Home Assistant hostnames

## Acceptance Criteria

- [x] `cloudflare-tunnel-secret` can be recreated by Flux after a fresh cluster-104
  bootstrap.
- [x] No Cloudflare tunnel secret value is stored unencrypted in Git.
- [x] The runbook documents the External Secrets ownership model.
