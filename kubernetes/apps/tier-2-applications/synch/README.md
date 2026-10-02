# Synch on cluster-101

Synch runs in the `default` namespace as one replica with `Recreate` deployment strategy. The Node API listens on port 8787 and both IP families (`HOST=::`). Its internal Cilium HTTPRoute serves <https://synch.sulibot.com>; `/health` is the readiness and liveness endpoint. Native authentication permits only `sulibot@gmail.com`.

The deployed source revision is `e781eb5d0e93`. The image is `ghcr.io/sulibot/synch-api:e781eb5d0e93`, pinned to digest `sha256:45e81e4a32d1767af9582a3598f5ef898079413d955524d98f2545cb65bf6a3e`. Initial GitOps integration was committed as `9217d27` on home-ops main. The Synch Flux Kustomization depends on `storage-ready`; the actual internal gateway was verified independently.

## DNS and access

Cloudflare has a DNS-only A record for `synch.sulibot.com` pointing to `10.101.250.11`, TTL 120. This DNS record is managed outside these Flux manifests. Clients require LAN or VPN routing to the private gateway address; DNS alone does not establish a VPN connection. TLS uses the gateway's existing wildcard certificate.

The HTTPRoute attaches only to `network/gateway-internal`. Cloudflare external-dns watches `gateway-tunnel`, so it does not manage this route's public DNS record. The existing internal Mikrotik external-dns controller was returning RouterOS HTTP 401 during deployment; automatic internal DNS updates require that separate credential issue to be repaired. The DNS-only Cloudflare record currently provides resolution without changing that controller.

## Secrets and registry credentials

`app/secret.sops.yaml` stores `BETTER_AUTH_SECRET` and `SYNC_TOKEN_SECRET`; `app/registry.sops.yaml` stores the `synch-registry` image pull credentials. Both encrypt secret data with the repository's SOPS age recipient. Flux decrypts through `flux-system/sops-age`. Preserve access to that age private key independently of the cluster. Never commit decrypted secrets.

To rotate the registry credential, create a replacement GitHub credential with package read access, replace the live `default/synch-registry` secret securely, and encrypt its replacement data into `app/registry.sops.yaml` using the same age recipient and `^(data|stringData)$` encrypted regex. Commit the encrypted replacement, reconcile Flux, and verify a fresh pod can pull the pinned image before revoking the previous credential. Avoid putting credentials in shell history, command output, or plaintext repository files.

Preserve the auth secrets when restoring the server. Rotating these secrets may invalidate active sessions and sync tokens.

## Persistent data and recovery

`default/synch-data` is a 5Gi ReadWriteOnce PVC using `csi-rbd-rbd-backups-sc-retain`, mounted at `/data`. It contains the application database, per-vault SQLite coordinator databases, and encrypted blobs. The storage class retains the underlying volume after PVC deletion; retention is not a backup. These manifests do not configure automatic data backups.

For a consistent full-server backup, stop Synch by scaling the deployment to zero, wait until its pod has terminated, and snapshot or copy the complete `/data` volume. Resume the single replica after the backup finishes. A full-server restore requires the matching complete `/data` backup and preserved auth secrets; avoid independently restoring SQLite files and blobs from different times. Restore the volume while Synch is stopped, retain ownership compatible with UID/GID 1000, then start the deployment and verify HTTPS `/health`, native login, and vault synchronization. Coordinate temporary scale changes with Flux so reconciliation does not restart the server during the backup.

Git history contains deployment configuration and encrypted secrets, not a backup of synchronized vault data. Back up client vaults separately as well.
