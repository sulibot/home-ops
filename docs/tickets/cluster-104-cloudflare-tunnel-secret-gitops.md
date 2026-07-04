---
title: Move cluster-104 Cloudflare tunnel credentials under GitOps secret management
status: open
created: 2026-07-04
cluster: cluster-104
area: cloudflare
---

## Summary

`cluster-104` now runs its own Cloudflare Tunnel for Home Assistant external
WARP access. The tunnel credentials are currently stored as a live Kubernetes
Secret named `cloudflare-tunnel-secret` in the `network` namespace.

This is operationally correct but not fully GitOps-recoverable. A cluster
rebuild would require recreating that Secret manually before `cloudflared` can
connect.

## Current State

- Cloudflare tunnel name: `cluster-104`
- Cloudflare tunnel ID is stored in SOPS Terraform secrets as
  `cloudflare_tunnel_id_cluster_104`
- Public DNS for `hass.sulibot.com` and `hass-app.sulibot.com` points to the
  cluster-104 tunnel
- Kubernetes deployment:
  - `kubernetes/clusters/cluster-104/cloudflare-tunnel/`
- Live credential Secret:
  - namespace: `network`
  - name: `cloudflare-tunnel-secret`
  - keys: `credentials.json`, `config.yaml`

## Desired State

Choose one standard secret-management pattern for `cluster-104`:

1. Install External Secrets + 1Password Connect and mirror the cluster-101
   pattern.
2. Enable Flux SOPS decryption for `cluster-104` and commit an encrypted
   Secret manifest.

External Secrets is preferred if cluster-104 will host more infrastructure
services. SOPS is simpler if the cluster remains narrowly scoped to Home
Assistant and adjacent services.

## Acceptance Criteria

- `cloudflare-tunnel-secret` can be recreated by Flux after a fresh cluster-104
  bootstrap.
- No Cloudflare tunnel secret value is stored unencrypted in Git.
- The runbook documents how to rotate the tunnel secret and update the cluster.
