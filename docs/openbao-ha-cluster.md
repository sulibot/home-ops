# OpenBao HA cluster

## Design

OpenBao runs as three Debian 13 LXCs, one per Proxmox node:

| Member | Proxmox node | IPv4 | IPv6 |
|---|---|---|---|
| `openbao01` | `pve01` | `10.100.0.68` | `fd00:100::68` |
| `openbao02` | `pve02` | `10.100.0.69` | `fd00:100::69` |
| `openbao03` | `pve03` | `10.100.0.70` | `fd00:100::70` |

The members use OpenBao Integrated Storage (Raft). Each member has its own
Ceph-backed data volume mounted at `/opt/openbao/data`; the three volumes are
not a shared filesystem. The data mount is explicitly included in Proxmox
guest backups, and each container has Proxmox deletion protection enabled.

Clients use `https://openbao.sulibot.com`:

- IPv4 service VIP: `10.100.240.67/32`
- IPv6 service VIP: `fd00:100:0:240::67/128`

For browser OIDC, only `idm.sulibot.com` is published through the main
Cloudflare Tunnel so Kanidm remains reachable during the external identity
handoff. It bypasses Authentik-backed Cloudflare Access because Kanidm is the
identity provider for both Authentik and OpenBao; protecting the IdP with its
own downstream identity chain would create a circular dependency.

`openbao.sulibot.com` remains private and resolves to the leader-gated service
VIP through split DNS. The tunnel has an explicit `http_status:404` rule for
that hostname ahead of the wildcard application route, preventing accidental
publication even when wildcard public DNS resolves the name.

This is a leader-gated BGP floating VIP, not active-active ECMP. Every member
maintains BGP sessions to its local Proxmox FRR anycast gateway, but a health
timer enables the service routes only when `/v1/sys/health` identifies that
member as initialized, unsealed, and active. Standbys do not normally receive
client traffic.

True all-node anycast would work because OpenBao standbys can forward requests
to the active member, but it would add a second network hop to most requests
without adding write capacity. Keeping one route origin also makes client
traffic follow the same failure decision as Raft leadership.

The VIPs deliberately sit outside `10.100.0.0/24` and `fd00:100::/64`.
Clients therefore route through the fabric instead of attempting on-link
ARP/NDP for addresses assigned to the members' loopback interfaces.

Node-specific DNS names remain available for initialization, unsealing,
maintenance, and recovery. OpenBao request forwarding over port `8201` remains
enabled as a safety net. The OpenBao host routes are also included in the
Tailscale and Cloudflare WARP private-route catalogs.

## Deployment

Apply local DNS before the OpenBao unit so certificate validation and
node-specific API addresses work:

```bash
cd terraform/infra/live/routeros
terragrunt apply

cd ../services/openbao
terragrunt apply
```

After the cluster endpoint is healthy, plan and apply
`services/tailscale-config` and `services/cloudflare-access` separately to
publish the two new private host routes for remote clients.

OpenBao uses GCP Cloud KMS as an independent auto-unseal service. Terraform
validates the restricted KMS principal in the `openbao-gcp-kms` 1Password
document, streams it to a root-owned credential file, and starts each member.
The credentials and initialization output never become Terraform inputs or
state.

The service account receives a custom role containing only
`cloudkms.cryptoKeyVersions.useToEncrypt`,
`cloudkms.cryptoKeyVersions.useToDecrypt`, and `cloudkms.cryptoKeys.get`, scoped
to the one OpenBao key.

Create an asymmetric administrative boundary around the KMS key: keep
key-version disable/destroy and IAM administration away from the OpenBao
principal, and protect the administrative account with MFA. Keep one active
software key version for the homelab seal. Automatic cryptographic rotation
would accumulate billable versions and does not revoke a leaked
service-account credential; rotate the restricted credential annually and
after any suspected exposure. The default configuration expects:

- GCP project: `sulibot-openbao-kms`
- KMS location: `global`
- KMS key ring: `openbao`
- KMS key: `auto-unseal`
- 1Password vault: `Kubernetes`
- 1Password document: `openbao-gcp-kms`

Override these non-secret selectors with
`OPENBAO_GCP_KMS_PROJECT_ID`, `OPENBAO_GCP_KMS_LOCATION`,
`OPENBAO_GCP_KMS_KEY_RING`, `OPENBAO_GCP_KMS_CRYPTO_KEY`,
`OPENBAO_GCP_KMS_1PASSWORD_VAULT`, and
`OPENBAO_GCP_KMS_1PASSWORD_ITEM`.

Terraform deliberately does not initialize OpenBao because `bao operator init`
returns recovery shares and the initial root token. Putting that operation in
Terraform would expose recovery material in state or apply logs.

## One-time initialization

Run initialization from a trusted operator workstation:

```bash
nix shell nixpkgs#openbao
export VAULT_ADDR=https://openbao01.sulibot.com
umask 077
bao operator init -key-shares=5 -key-threshold=3
```

Use recovery shares with the GCP KMS seal:

```bash
bao operator init -recovery-shares=5 -recovery-threshold=3
```

Store each recovery share as a separate 1Password item, keep the initial root
token separate, and retain an independently encrypted offline copy. SOPS key
groups with independent recipients are suitable for that backup; the single
age recipient currently used by this repository is not an independent quorum.
Do not save recovery material in this repository, the OpenBao LXCs, Kubernetes
Secrets, or Terraform state.

Recovery shares authorize privileged recovery operations, but cannot decrypt
the barrier if the KMS key is unavailable or permanently deleted. Preserve the
KMS administrative account and key for at least as long as any OpenBao data or
snapshot.

The first member unseals automatically after initialization. The other members
use `retry_join`, join the initialized cluster, and auto-unseal. Verify
membership and the client endpoint:

```bash
export VAULT_ADDR=https://openbao.sulibot.com
bao operator raft list-peers
bao status
curl --fail https://openbao.sulibot.com/v1/sys/health
```

## Routing verification

On the active member, both static service protocols should be enabled:

```bash
birdc show protocols service_vip4
birdc show protocols service_vip6
```

On each standby they should be disabled. All members should retain established
`upstream4` and `upstream6` BGP sessions:

```bash
birdc show protocols all upstream4
birdc show protocols all upstream6
```

Force a leadership test only during a maintenance window:

```bash
bao operator step-down
```

The former leader should withdraw both routes and the newly elected leader
should originate them. Verify the client endpoint throughout the test.

## Production integrations

The integration bootstrap is intentionally separate from Terragrunt. It uses
the root token only while reconciling mounts, policies, audit devices, and auth
methods; neither the token nor generated credentials enter Terraform state:

```bash
(
  cd terraform/infra/live/services/openbao
  ./rolling-reconcile.sh
  ./configure-kanidm-oidc.sh
  ./configure-integrations.sh
)
```

The configured ownership boundaries are:

- Kanidm groups `openbao-admins` and `openbao-readers` authenticate humans by
  OIDC. The admin policy explicitly denies raw storage, rekey, generate-root,
  seal, and audit-device mutation. The bootstrap human credential is stored
  separately as the `kanidm-sulibot` 1Password item.
- External Secrets authenticates with a projected service-account JWT and the
  IPv6 Kubernetes TokenReview API. Its short-lived JWT has both the `openbao`
  and IPv6 API-server audiences so it can self-review without a persistent
  reviewer token. The role can read only `kv/kubernetes/*`.
- OpenTofu, Ansible, and SOPS each use a separate AppRole and policy. Their
  RoleID/SecretID pairs are stored in distinct 1Password items and mint
  one-hour batch tokens.
- SOPS encrypts new files to both the retained age recipient and
  `transit/keys/sops` in the same key group. Either recipient can recover the
  data key; Flux bootstrap remains age-only and does not depend on OpenBao.
- The file and syslog audit devices are both enabled. Local audit files rotate
  safely with `SIGHUP`; rsyslog forwards the security stream to Fluent Bit on
  TCP 2515 for Loki and the VictoriaLogs trial. The receiver is dual-stack,
  but tenant 100 currently uses its IPv4 VIP until the fabric forwards the
  Cilium LoadBalancer IPv6 `/128` across tenants.

Use a scoped automation session instead of exporting the root token:

```bash
./scripts/openbao-approle-exec.sh tofu terragrunt plan
./scripts/openbao-approle-exec.sh ansible ansible-playbook playbook.yml
./scripts/sops-openbao.sh decrypt path/to/secret.sops.yaml
```

Plain `sops decrypt` continues to exercise the offline age recovery path.

### Kubernetes pilot

`immich-frame` is the first existing application migrated to the OpenBao
ClusterSecretStore. `radarr-4k` is the operational pilot: it exercises both
the application's API/database Secret and the CNPG-managed role-password
Secret. The bootstrap verifies that both rendered database passwords match,
then copies the current values into `kv/kubernetes/radarr-4k` before either
ExternalSecret source changes. This makes each cutover a source change without
a simultaneous credential rotation. Validate the cutovers without printing
values:

```bash
kubectl get clustersecretstore openbao
kubectl -n default get externalsecret immich-frame
kubectl -n default get externalsecret radarr-4k radarr-4k-pg-password
kubectl -n default rollout status deployment/immich-frame
kubectl -n default rollout status deployment/radarr-4k
curl --fail https://immich-frame.sulibot.com
curl --fail https://radarr-4k.sulibot.com/ping
```

Keep 1Password Connect deployed during the pilot and broader migration. It
remains the bootstrap/break-glass credential store; only explicitly migrated
application secrets move to OpenBao.

### Observability

Each member exposes unauthenticated Prometheus metrics only on its private
node address at TCP 9101. The public 443 listener continues to reject
unauthenticated metrics. Kubernetes supplies a fixed IPv6 Endpoints object,
ServiceMonitor, OpenBao dashboard, and alerts for member reachability, sealed
state, Raft health, and audit-write failures.

The Grafana dashboard is in the `security` folder. Audit events have the Loki
label `source_type="openbao-audit"`; secret values remain HMACed by OpenBao.

## TLS rotation

The Terragrunt unit reads the existing public wildcard certificate from the
Kubernetes `network/sulibot-com-tls` Secret, with 1Password as a fallback.
The private key is streamed directly to the members and never enters Terraform
state. OpenBao reloads the listener pair with `SIGHUP` and does not seal.

Force a certificate refresh after wildcard renewal:

```bash
cd terraform/infra/live/services/openbao
terragrunt apply -replace=null_resource.openbao_tls_sync
```

## Backups

Proxmox guest backups are useful for reconstructing the LXCs but are not a
replacement for an application-consistent Raft snapshot:

```bash
export VAULT_ADDR=https://openbao.sulibot.com
bao operator raft snapshot save openbao-$(date -u +%Y%m%dT%H%M%SZ).snap
```

Encrypt and copy snapshots outside the Proxmox/Ceph failure domain. Periodically
test a force-restore in an isolated environment.

The deployed `openbao-backup.timer` automates this every six hours on all three
members. A snapshot-only AppRole identifies the active leader, which saves and
checksum-validates the Raft archive before uploading it directly to the
30-day-governance `sulibot-infrastructure-immutable` B2 bucket. Standbys exit
successfully without writing duplicate snapshots. Kubernetes' monitored
`minio-selected-offsite-copy` job also fails if no B2 OpenBao snapshot is newer
than eight hours.

## Upgrades and configuration changes

The provisioning script refuses to upgrade an initialized member in place.
Terraform provisions members concurrently, while OpenBao upgrades must be
performed sequentially:

1. Save and verify a Raft snapshot.
2. Upgrade one standby.
3. Start it, verify it auto-unseals, then verify it has caught up.
4. Repeat for the other standby.
5. Step down the active node.
6. Upgrade and unseal the former leader.

The same rolling procedure applies to configuration changes that require a
restart. Certificate-only changes use `SIGHUP` and do not require this process.
The provisioning guard intentionally refuses to introduce or change a seal on
an initialized member because seal migration is a separate, cluster-wide
procedure.

For a source-controlled non-seal configuration change, run the guarded rolling
reconciler. It verifies three healthy members before each restart, processes
standbys before the leader, verifies auto-unseal, and tests the private metrics
listener after every member:

```bash
cd terraform/infra/live/services/openbao
./rolling-reconcile.sh
```

## Auto-unseal

OpenBao and its LXC start automatically. At process startup OpenBao reads the
root-owned GCP service-account file, asks Cloud KMS to decrypt its barrier key,
rejoins Raft, and becomes an eligible leader without operator input. The BGP VIP
remains withdrawn until a member is initialized, unsealed, and elected active.

Test this before relying on it:

1. Restart one standby and verify `/v1/sys/seal-status` reports
   `"type":"gcpckms"` and `"sealed":false`.
2. Repeat for the other standby.
3. Step down the leader, restart the former leader, and verify the VIP remains
   reachable.
4. During a maintenance window, restart all three LXCs and verify automatic
   Raft recovery.
5. Temporarily deny one standby access to KMS and verify it stays sealed while
   the other two members remain healthy; restore access and verify it recovers.

Rotate the restricted IAM access key by updating the 1Password item, then run:

```bash
cd terraform/infra/live/services/openbao
terragrunt apply -replace=null_resource.openbao_kms_credentials_sync
```

The cluster has a strict lifecycle dependency on the KMS key and GCP
availability. 1Password is the credential distribution and break-glass tool;
it is not the seal. SOPS Transit is an online convenience and secondary
recipient; the retained age key is the offline recovery path.

References:

- [OpenBao High Availability](https://openbao.org/docs/concepts/ha/)
- [Integrated Storage (Raft)](https://openbao.org/docs/configuration/storage/raft/)
- [GCP Cloud KMS auto-unseal](https://openbao.org/docs/configuration/seal/gcpckms/)
- [Seal and recovery-key lifecycle](https://openbao.org/docs/concepts/seal/)
- [`/sys/health`](https://openbao.org/api-docs/system/health/)
