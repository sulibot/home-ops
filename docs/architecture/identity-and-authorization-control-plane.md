# Identity and authorization control plane

Status: current-state audit and target model
Owners: SRE / identity / platform
Last reviewed: 2026-07-29

## Purpose

This document defines where identities, groups, numeric Unix IDs, application
roles, and Kubernetes permissions are authoritative. It covers Kanidm,
Authentik, Proxmox, Kubernetes, OpenBao, OpenCloud, CephFS/NFS, and the
observability stack.

Authentication proves who a principal is. Group membership grants an
entitlement. A workload's Kubernetes namespace is classification metadata; it
is not a directory of people and must never be treated as one.

## Authority model

| Concern | Authority | Consumer |
|---|---|---|
| Human infrastructure identity | Kanidm person UUID | Unix, Proxmox, OpenBao, future Kubernetes human OIDC |
| Unix UID, primary GID, supplemental GIDs | Kanidm POSIX account/groups | `kanidm-unixd`, CephFS, NFSv4 `sec=sys` |
| App-only or externally authenticated person | Authentik user UUID | Authentik-backed applications |
| Login credentials | Kanidm, Google, or Authentik break-glass | Authentik source connections |
| App entitlement | Authentik application group | Authentik policy and app role claim |
| Infrastructure entitlement | Kanidm group | Direct OIDC/POSIX consumer |
| Kubernetes API authorization | Kubernetes RBAC | OIDC group claim after human OIDC is enabled |
| Secret policy | OpenBao policy and external group alias | OpenBao token |
| Data placement | CephFS | OpenCloud PosixFS, NFS, Syncthing |
| App service identity | Workload security context | ACL only; never a human UID |

The same person may have one Kanidm record and one Authentik broker record. The
records are joined by immutable UUIDs. Email and username are mutable
attributes, not join keys.

## Canonical `sulibot` identity

| Field | Value | Meaning |
|---|---|---|
| Kanidm UUID | `1a8cb2c5-a67a-4010-a01b-43db708ec7e5` | canonical infrastructure identity |
| Kanidm name | `sulibot` | human-readable login name |
| Kanidm POSIX UID/primary GID | `1888405477` | canonical file and process identity |
| Authentik UUID | `0b75cb54-d109-4876-bf4a-cc90a570134c` | stable app-broker identity |
| Authentik username | `sulibot` | broker username |
| Email | `sulibot@gmail.com` | contact and verified login attribute |
| Google subject | `104864399168196898615` | alternate Authentik credential |
| Kanidm OIDC subject | Kanidm UUID above | alternate Authentik credential |

The Authentik UUID is random and carries no numeric identity semantics.
Keeping it preserves existing hashed OIDC subjects. The Google and Kanidm
source connections both authenticate the same Authentik user; neither creates
a second application person.

UID/GID `1000` is reserved here for OpenCloud and Syncthing workload service
identities. It is granted explicit ACL access and is not the owner identity of
the human's personal tree.

## Group classes and naming

Groups are intentionally separated by what they authorize.

| Pattern | Authority | Example | Grants |
|---|---|---|---|
| `<app>-users`, `<app>-admins` | Authentik | `opencloud-users` | app login or app role |
| `<service>-readers`, `<service>-admins` | Kanidm | `openbao-admins` | direct infrastructure service policy |
| `storage_<name>_rw` | Kanidm POSIX | `storage_common_rw` | numeric filesystem access |
| `k8s_<namespace>_view` | Kanidm | `k8s_observability_view` | Kubernetes read-only RBAC |
| `k8s_<namespace>_edit` | Kanidm | `k8s_observability_edit` | namespaced workload mutation |
| `k8s_<namespace>_admin` | Kanidm | `k8s_observability_admin` | namespaced RBAC administration |

Do not reuse an unrelated group because its current members happen to be
correct. For example, `grimmory-admins` must not imply OpenCloud
administration, and `standard-users` must not become a universal app-admin
role.

An application group and an infrastructure group may be mapped deliberately,
but they remain separate entitlements. This permits Google-only Authentik users
to use applications without receiving a POSIX identity or Kubernetes access.

## Practical baseline group catalog

Start with access domains, then add a dedicated app group only when the app
has a distinct audience or internal role. This avoids both one universal group
and one group per workload.

### Authentik application groups

| Group | Intended use |
|---|---|
| `observability-users` | Grafana and other safe read-only observability UIs |
| `observability-admins` | observability application administration; not Kubernetes access |
| `media-users` | household media and library applications |
| `media-admins` | media application administration |
| `home-users` | Home Assistant and household-control applications |
| `home-admins` | household-control administration |
| `productivity-users` | documents, feeds, tasks, bookmarks, and similar personal apps |
| `productivity-admins` | administration for that app domain |
| `opencloud-users` | OpenCloud login and ordinary system role |
| `opencloud-admins` | OpenCloud system administration |
| `grimmory-users` | Grimmory application access |
| `grimmory-admins` | Grimmory application administration only |
| `authentik-admins` | Authentik control plane; very small membership |

`standard-users`, `trusted-users`, and `infrastructure-users` remain
transitional compatibility groups until each existing application is assigned
to an access domain. They should not be used for new applications.

### Kanidm infrastructure groups

| Group | Intended use |
|---|---|
| `unix_workstations_users` | interactive login to semi-disposable user workstations |
| `unix_servers_admins` | privileged server login; small membership |
| `storage_common_rw` | Common Space NFS/POSIX write access |
| `storage_common_ro` | future read-only Common export if required |
| `openbao-readers` | OpenBao read-only human policy |
| `openbao-admins` | OpenBao administrative human policy |
| `proxmox-auditors` | read-only Proxmox access |
| `proxmox-operators` | VM/LXC lifecycle without platform administration |
| `proxmox-admins` | full Proxmox administration; very small membership |
| `k8s_<namespace>_view` | Kubernetes read-only RoleBinding in one namespace |
| `k8s_<namespace>_edit` | routine namespaced workload changes |
| `k8s_<namespace>_admin` | namespaced RBAC and workload administration |
| `k8s_cluster_auditors` | cluster-wide read-only access |
| `k8s_cluster_admins` | exceptional cluster administration; never map to `system:masters` |
| `minio-readers`, `minio-writers`, `minio-admins` | direct MinIO OIDC policy tiers |
| `zot-readers`, `zot-writers`, `zot-admins` | direct registry policy tiers |
| `pki-users`, `pki-admins` | certificate enrollment versus CA administration |

Do not use Kanidm's broad `posix_group` as the final PAM allow-list. It means
"has a POSIX identity", not "may log into this machine." Client classes should
eventually use the explicit workstation or server group.

### Machine identities

Humans must not be placed into service-account groups. Kubernetes
ServiceAccounts, OpenBao AppRoles/Kubernetes auth roles, CephX clients,
Proxmox API tokens, monitoring scrapers, and backup agents each retain a
separate machine credential and narrowly scoped policy.

## Namespace-based application access

Kubernetes does not have human namespace membership. A namespace can declare
the default app entitlement as metadata:

```yaml
metadata:
  labels:
    access.sulibot.com/default-app-group: observability-users
```

The intended policy is:

1. A user in `observability-users` may authenticate to user-facing apps whose
   deployment declares that namespace default.
2. Each Authentik application or forward-auth provider must bind the declared
   group. CI checks this relationship.
3. An application may override the namespace default with a narrower dedicated
   group.
4. `k8s_observability_view|edit|admin` controls Kubernetes API access and is
   never implied by `observability-users`.
5. Moving a workload between namespaces is an authorization change and requires
   review.

This convention is not active yet. Most tier-2 applications currently run in
`default`, and the API server has no human OIDC configuration. Namespace
migration, Authentik policy generation, and Kubernetes OIDC/RBAC must land as a
reviewed change set.

## Current alignment

| Plane | Current state | Assessment |
|---|---|---|
| Kanidm to Authentik identity | `sulibot` Kanidm subject and Google subject are linked to one Authentik UUID | aligned |
| Kanidm POSIX to NFS | personal UID/GID `1888405477`; Common group GID `1965604563` | aligned |
| OpenCloud | dedicated `opencloud-users` and `opencloud-admins`; POSIX entitlement separate | aligned |
| OpenBao | Kanidm `openbao-admins`/`openbao-readers` map to external groups and policies | aligned |
| Authentik apps generally | mostly coarse `standard-users` and `trusted-users` policies | transitional |
| Grafana | Authentik `trusted-users` gives Admin and `standard-users` gives Editor | transitional; replace with Grafana/observability groups |
| Kubernetes API | client certificates/system groups only; no human OIDC groups or namespace RoleBindings | not implemented |
| Proxmox | `idm` realm exists, but the live Kanidm `proxmox` OAuth client and group mapping are absent | incomplete |
| Monitoring | NFS server and client probes exist; identity/group drift coverage is not yet complete | partial |

## Target request paths

### App login

```text
Kanidm or Google credential
  -> Authentik source connection
  -> one Authentik user UUID
  -> app-specific Authentik group
  -> Authentik application policy / role claim
  -> application account
```

### Unix and shared storage

```text
Kanidm person UUID
  -> Kanidm POSIX UID and groups
  -> kanidm-unixd NSS/PAM
  -> NFSv4 numeric identity
  -> CephFS owner/group/ACL
```

### OpenBao

```text
Kanidm group
  -> Kanidm OIDC groups claim
  -> OpenBao external-group alias
  -> OpenBao policy
```

### Kubernetes API (target)

```text
Kanidm k8s_<namespace>_<role> group
  -> per-cluster Kanidm public OIDC client
  -> kube-apiserver groups claim with a fixed prefix
  -> namespaced RoleBinding
  -> ClusterRole view/edit or a reviewed namespaced admin role
```

Use one OIDC client per cluster. Do not share the Authentik or OpenBao client,
because audiences, redirect URIs, scopes, and compromise boundaries differ.

## Provisioning and deprovisioning

For an infrastructure user:

1. Create one Kanidm person and record its UUID.
2. Enable POSIX once; record the generated UID/primary GID.
3. Add only the required Kanidm infrastructure/POSIX groups.
4. Create or select one Authentik user and record its UUID.
5. Attach each external source subject to that same Authentik user.
6. Add explicit Authentik app groups.
7. Create storage only after numeric identity is known.

For an app-only user, omit Kanidm and all POSIX/Kubernetes groups. Google or an
Authentik-local credential may authenticate the Authentik app account.

Deprovision by removing entitlement groups first, revoking sessions/tokens
second, and retaining the disabled identity for the audit/retention period.
Deleting a login source must not delete the canonical person or their data.

## Monitoring and audit

Required controls:

- alert when Kanidm replication or OIDC discovery is unhealthy;
- alert when Authentik source/provider blueprints fail;
- alert when OpenBao OIDC login or group aliases drift;
- alert when NFS export, failover, or canonical-UID write probes fail;
- inventory Authentik users with multiple source connections and flag a source
  subject attached to more than one person;
- compare recorded Kanidm UUID/UID/GID inventory to live NSS and CephFS
  ownership;
- validate that namespace default app groups exist and every exposed app has an
  access policy;
- validate that Kubernetes RoleBinding group names are present in Kanidm;
- audit privileged group membership and stale sessions on a schedule.

Break-glass credentials for Authentik, Grafana, OpenBao, Kubernetes, and
Proxmox remain independent, strongly protected, and tested without making them
normal daily identities.

## Design references

- Kubernetes, [RBAC good practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)
- Kanidm, [POSIX accounts and groups](https://kanidm.github.io/kanidm/stable/accounts/posix_accounts_and_groups.html)
- Kanidm, [OAuth2 custom claims](https://kanidm.github.io/kanidm/stable/integrations/oauth2/custom_claims.html)
- Authentik, [application access policies](https://docs.goauthentik.io/add-secure-apps/applications/manage_apps/)
- OpenBao, [JWT/OIDC group claims](https://openbao.org/docs/auth/jwt/)
- OpenCloud, [Space roles](https://docs.opencloud.eu/docs/user/roles/space-roles)
