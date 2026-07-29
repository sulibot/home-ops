# User storage, identity, and synchronization

Status: initial single-user implementation (`sulibot`)
Owners: SRE / storage / identity
Last reviewed: 2026-07-29

## Purpose

Provide one canonical user file tree that is usable through:

- direct POSIX access from Proxmox VMs and LXCs;
- OpenCloud web, desktop, and iOS clients;
- Syncthing full offline replicas;
- Kubernetes workloads that are explicitly authorized.

This design does not make the entire Unix home directory roam. It exposes
`/home/<user>/Cloud`; host configuration remains declarative and caches,
credentials, sockets, browser profiles, and application databases remain local.

## Decisions

1. CephFS `content` is the canonical online file plane.
2. The interoperable namespace is `/users/<user>/Cloud`.
3. OpenCloud and Syncthing state use separate PVCs. They share only the user
   file tree.
4. Syncthing is single-user. `syncthing-sulibot` serves only `sulibot`; each
   future user receives a separate instance, device graph, config PVC, and
   CephFS root.
5. Kanidm is authoritative for infrastructure identities and POSIX
   attributes. Authentik is authoritative for application-facing accounts
   and may contain a broader population.
6. Kubernetes and guest mounts use path-restricted CephX identities. CephX
   authenticates the machine; Kanidm UID/GID plus POSIX ACLs authorize the
   process.
7. Syncthing replication is availability, not backup. CephFS snapshots and an
   independent backup target remain required.

## Architecture

```text
Kanidm person UUID ── POSIX UID/GID ───┐
   └── explicitly linked ── Authentik ─┼── OIDC ── OpenCloud
Google ── login source ────────────────┤
Authentik-local login ─────────────────┘
                                      ▼
CephFS content:/users/sulibot/Cloud
   ├── OpenCloud PosixFS collaborative access
   ├── syncthing-sulibot pod
   ├── native CephFS mount in VMs
   └── PVE-host mount + bind mount in trusted, UID-compatible LXCs

Mac ── Syncthing local replica
iPhone ── OpenCloud client/selective offline files
```

## Identity and authorization

### Supported identity classes

| Class | Authentication | Kanidm POSIX identity | Unix/storage entitlement |
|---|---|---|---|
| Infrastructure user | Kanidm; optionally explicitly linked Google | Required | Granted by infrastructure groups |
| Google-only application user | Google through Authentik | None | None |
| Authentik-local application user | Authentik credential/passkey | None | None |
| Authentik-local break-glass admin | Strong local passkey/MFA | None required | Administrative control plane only |

Authentication source is not an authorization signal. Google-only and
Authentik-local accounts may use applications allowed by their Authentik
groups, but they do not receive a numeric Unix identity, CephFS directory,
CephX key, VM/LXC login, or Syncthing instance.

For an infrastructure user, the immutable Kanidm person UUID is the identity
join key. Email and username are mutable display/routing attributes and must
not be used to merge accounts or grant storage. Authentik keeps one
application-facing account and may attach multiple authenticated source
connections to it.

| Layer | Identity | Responsibility |
|---|---|---|
| Infrastructure identity | Kanidm person UUID | Canonical person, groups, POSIX extension |
| Application account | Authentik user UUID / OIDC subject | Stable relying-party identity |
| Login method | Kanidm, Google, or Authentik-local | Prove control of an account |
| Filesystem client | CephX | Restrict a machine/pod to `/users/sulibot` |
| File access | numeric UID/GID and ACL | Read/write authorization |
| Syncthing | device certificate | Per-device folder replication |

OpenCloud's OIDC subject and Kanidm's numeric POSIX ID are not assumed to be
the same value. Provisioning resolves the Kanidm UID/GID and applies an ACL to
the user's directory. OpenCloud and Syncthing run as service UID/GID 1000 and
receive an explicit ACL. Future automation should record the Kanidm account
UUID and numeric IDs in a generated, non-secret user-storage inventory.

### Linking `sulibot` to Google

The current Google and Kanidm source blueprints both use
`user_matching_mode: identifier`. This safely avoids automatic email-based
merging, but a first login through each source creates separate Authentik
accounts unless the source connection is deliberately attached.

1. Sign in to Authentik through Kanidm as the canonical `sulibot` account.
2. From that authenticated account, connect the Google source, or have an
   administrator link the exact Google issuer and subject.
3. Verify both login paths return the same Authentik user UUID and the same
   OIDC `sub` to OpenCloud.
4. Record the Kanidm UUID on the Authentik account as a managed attribute.
5. Keep Google enrollment for unprovisioned identities application-only and
   never infer infrastructure membership from the email claim.
6. Retain a Kanidm passkey and tested Authentik-local break-glass
   administrators so Google is not a recovery dependency.

At least two break-glass accounts should use strong passkeys/MFA, have no
ordinary application access, be stored in the password manager, generate
login alerts, and be tested quarterly.

### Promotion to infrastructure access

To promote an existing Google-only or Authentik-local user:

1. Create and POSIX-enable the Kanidm person.
2. Capture its immutable Kanidm UUID and numeric UID/GID.
3. Explicitly link the existing Authentik account to that Kanidm person.
4. Add the infrastructure and storage entitlement groups.
5. Provision the CephFS namespace, ACL, CephX identity, and per-user
   Syncthing instance.

This preserves the application account and its data. Deleting or unlinking a
Google login must not delete the Kanidm person or user files.

## Storage layout

| Path/storage | Owner |
|---|---|
| `content:/users/sulibot/Cloud` | canonical shared files |
| `syncthing-sulibot-config` RBD PVC | Syncthing certificate, database, configuration |
| `opencloud-config` RBD PVC | OpenCloud configuration, NATS, indexes, metadata |
| VM/LXC root on `rbd-vm` | disposable guest OS |
| `/home/sulibot/Cloud` | guest presentation of canonical files |

The CephFS directory is retained independently of Kubernetes object deletion.
Do not mount the root of `content` into either application.

## Access matrix

| Client | Access method | Offline behavior |
|---|---|---|
| NixOS/Debian VM | kernel CephFS client with path-scoped CephX key | requires homelab/Ceph |
| NixOS/Debian LXC | PVE CephFS mount bind-mounted as `mp0`; privileged or explicit 1:1 idmap | requires homelab/Ceph |
| macOS | Syncthing folder, e.g. `~/Cloud` | complete local replica |
| OpenCloud desktop | OpenCloud sync folder | local selected/full replica |
| iPhone/iPad | OpenCloud iOS app | on-demand or explicitly offline files |

Never point both the OpenCloud desktop client and Syncthing at the same local
directory. Pick one synchronization engine per local path.

## Client instructions

### VM

Install the Kanidm Unix client, `ceph-common`, `acl`, and `attr`. Enroll the
path-scoped secret as:

```text
/etc/ceph/ceph.client.sulibot-cloud.secret
```

Mount `sulibot-cloud@.content=/users/sulibot/Cloud` at
`/home/sulibot/Cloud`. Confirm:

```sh
getent passwd sulibot
findmnt /home/sulibot/Cloud
touch /home/sulibot/Cloud/.vm-write-test
getfattr -d /home/sulibot/Cloud/.vm-write-test
```

Delete only the test file after it appears in OpenCloud and Syncthing.

### LXC

The container receives no Ceph key. Proxmox mounts `content` and passes only:

```text
/mnt/pve/content/users/sulibot/Cloud -> /home/sulibot/Cloud
```

The bind source must exist on every PVE node and the mount point must be marked
shared. Validate Kanidm resolution and mapped ownership before enabling user
write access. `vzdump` does not back up bind-mounted content.

Proxmox unprivileged containers remap container UIDs/GIDs into a subordinate
host range. A plain bind mount therefore does not preserve the Kanidm numeric
identity, and Proxmox documents that ACLs can be problematic in this mode.
The initial single-user validation LXCs are deliberately privileged so the
Kanidm UID/GID is identical on CephFS and in the container. Treat this as a
security exception:

- use a VM for untrusted or multi-tenant work;
- bind only the dedicated user directory, never a system or CephFS root;
- keep AppArmor/seccomp and the normal container restrictions enabled;
- do not grant a Ceph key to the container;
- if privileged LXCs are no longer acceptable, implement and validate a
  narrow 1:1 LXC idmap for every entitled Kanidm UID/GID before switching.

### macOS Syncthing

Install Syncthing, add the device ID shown by `syncthing-sulibot`, and accept
the `sulibot-cloud` folder into `~/Cloud`. Enable staggered file versioning.
Use Tailscale-routed/LAN connectivity; the transfer listener is not publicly
exposed.

### OpenCloud desktop

Sign in at `https://opencloud.sulibot.com` through Authentik. Select a local
directory that is not managed by Syncthing. OpenCloud is appropriate when
selective sync, sharing, or the same experience as iOS matters more than peer
to-peer replication.

### iPhone/iPad

Install the OpenCloud iOS client, connect to
`https://opencloud.sulibot.com`, and authenticate through Authentik. Use
**Make available offline** for files required away from the network. iOS
offline availability is selective and is not a complete Syncthing-style
replica.

## OpenCloud requirements

OpenCloud uses PosixFS collaborative mode because direct mounts and Syncthing
modify the tree externally. Required settings include:

```text
STORAGE_USERS_DRIVER=posix
STORAGE_USERS_POSIX_ROOT=/srv/user-files
STORAGE_USERS_POSIX_WATCH_FS=true
STORAGE_USERS_POSIX_WATCH_TYPE=inotifywait
STORAGE_USERS_POSIX_WATCH_PATH=/srv/user-files
```

The OpenCloud `cephfs` watcher type consumes CephFS change notifications from
Kafka; it is not a direct watcher for a mounted CephFS tree. This stack does not
run Kafka, so it uses `inotifywait` on the mounted tree. Validate cross-client
create, update, rename, and delete events before expanding beyond `sulibot`.

Bulk moves between OpenCloud Spaces, symlinks, and mass external deletion are
not supported operating patterns. Stop writers before bulk maintenance.

The pinned OpenCloud 5.2.0 image is deployed with
`OC_EXCLUDE_RUN_SERVICES=search`: on a new config volume this release
reproducibly creates an empty Bleve mapping and exits. Search is not required
for sync, WebDAV, direct file access, or iOS access. Remove the exclusion only
after validating a newer OpenCloud release against a freshly created index.

## Failure behavior

| Failure | Effect | Recovery |
|---|---|---|
| laptop offline | local Syncthing/OpenCloud copies remain usable | reconnect and inspect conflicts |
| Syncthing down | direct mounts and OpenCloud continue | restore config PVC or re-enroll devices |
| OpenCloud down | direct mounts and Syncthing continue | restore config PVC; user files remain |
| Kanidm down | cached Unix identities may work; new auth fails | restore identity quorum |
| CephFS/MDS unavailable | all online canonical access stops | follow Ceph MDS runbook |
| concurrent edit | application or Syncthing conflict copy | preserve both and reconcile manually |

## Provisioning a future user

1. Create or identify the Authentik application account.
2. POSIX-enable the Kanidm person and private group.
3. Link the accounts by immutable Kanidm UUID; do not match on email.
4. Create `/users/<name>/Cloud`.
5. Create a path-restricted `client.<name>-cloud` CephX identity.
6. Apply owner, service-user ACL, and default ACL.
7. Create a retained static PV/PVC rooted at the user path.
8. Deploy `syncthing-<name>` with its own RBD config PVC.
9. Authorize and expose the user's tree through OpenCloud.
10. Validate write propagation from every authorized client.

## SLOs and alerts

- Alert when the Syncthing pod is unavailable for 15 minutes.
- Alert on out-of-sync items older than one hour while a peer is connected.
- Alert on CephFS near-full, MDS damage, or failed snapshots.
- Quarterly restore test for application state and user files.
- Review CephX caps and Syncthing device membership during user offboarding.

## Destructive reset

The original OpenCloud instance is disposable. The cutover runbook must scale
OpenCloud to zero, delete its old PVC only after the new manifests are ready,
recreate application state, and validate the new user tree before Syncthing is
allowed to write.
