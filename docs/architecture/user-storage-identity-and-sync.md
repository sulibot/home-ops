# User storage, identity, and synchronization

Status: personal storage plus organization-owned Common Space
Owners: SRE / storage / identity
Last reviewed: 2026-07-29

## Purpose

Provide one canonical user file tree that is usable through:

- direct POSIX access from Proxmox VMs and LXCs;
- OpenCloud web, desktop, and iOS clients;
- Syncthing full offline replicas;
- Kubernetes workloads that are explicitly authorized.

Provide a separate organization-owned Common Space for files intended for all
regular application users. A personal Space is never used as the ownership
anchor for communal data.

This design does not make the entire Unix home directory roam. It exposes
`/home/<user>/Cloud`; host configuration remains declarative and caches,
credentials, sockets, browser profiles, and application databases remain local.

## Decisions

1. CephFS `content` is the canonical online file plane.
2. The interoperable namespace is `/users/<user>/Cloud`.
3. OpenCloud and Syncthing state use separate RBD PVCs. Both file-data mounts
   reuse the exact `user-storage-opencloud` CephFS PVC and are co-scheduled on
   one node. This is required for OpenCloud's inotify assimilation to observe
   Syncthing changes in real time.
4. Syncthing is single-user. `syncthing-sulibot` serves only `sulibot`; each
   future user receives a separate instance, device graph, config PVC, and
   CephFS root.
5. Kanidm is authoritative for infrastructure identities and POSIX
   attributes. Authentik is authoritative for application-facing accounts
   and may contain a broader population.
6. OpenCloud creates and owns every personal Space root and its extended
   attributes. Provisioning must never pre-create `/users/<user>/Cloud`.
   Kanidm UID/GID plus POSIX ACLs authorize raw Unix access, but independent
   CephFS/NFS clients do not participate in the real-time inotify domain.
7. Syncthing replication is availability, not backup. CephFS snapshots and an
   independent backup target remain required.
8. OpenCloud application users receive a stable `opencloud_username`. A
   Kanidm-backed `storage_username` is preferred when present; otherwise the
   Authentik username is used without granting any Unix entitlement.
9. Authentik `opencloud-users` and `opencloud-admins` may use OpenCloud. These
   dedicated groups are mirrored during JIT provisioning and grant access to
   the Common Space. NFS access remains the narrower Kanidm
   `storage_common_rw` POSIX entitlement.
10. OpenCloud system roles are assigned from Authentik groups:
    `opencloud-admins` maps to `opencloudAdmin`; other allowed users map to
    `opencloudUser`. An application-admin role does not imply NFS access.

## Architecture

```text
Kanidm person UUID ── POSIX UID/GID ───┐
   └── explicitly linked ── Authentik ─┼── OIDC ── OpenCloud
Google ── login source ────────────────┤
Authentik-local login ─────────────────┘
                                      ▼
CephFS content:/users
   ├── sulibot/Cloud
   │   ├── OpenCloud PosixFS collaborative access
   │   ├── syncthing-sulibot via the same PVC and Kubernetes node
   │   └── independent CephFS/NFS mounts (startup-scan visibility)
   └── projects/5348ae65-b9b1-406d-b9d4-1f9139933a37
       ├── OpenCloud organization-owned Common Space
       └── NFS-Ganesha /common

Mac ── Syncthing local replica
iPhone ── OpenCloud client/selective offline files
```

## Identity and authorization

### Supported identity classes

| Class | Authentication | Kanidm POSIX identity | Unix/storage entitlement |
|---|---|---|---|
| Infrastructure user | Kanidm; optionally explicitly linked Google | Required | Granted by infrastructure groups |
| Google-only application user | Google through Authentik | None | OpenCloud personal/Common access only |
| Authentik-local application user | Authentik credential/passkey | None | OpenCloud personal/Common access only |
| Authentik-local break-glass admin | Strong local passkey/MFA | None required | Administrative control plane only |

Authentication source is not an authorization signal. Google-only and
Authentik-local accounts may use applications allowed by their Authentik
groups, including OpenCloud-managed personal and Common Space storage. They do
not receive a numeric Unix identity, CephX key, VM/LXC login, NFS entitlement,
or Syncthing instance.

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

Current pilot identity link:

| Authentik UUID | Kanidm UUID | Storage name | UID / primary GID | Common GID |
|---|---|---|---:|---:|
| `0b75cb54-d109-4876-bf4a-cc90a570134c` | `1a8cb2c5-a67a-4010-a01b-43db708ec7e5` | `sulibot` | `1888405477` | `1965604563` |

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
| `content:/users/sulibot/Cloud` | OpenCloud-owned personal Space; UID/GID `1000:1000` plus canonical-user ACL |
| `content:/users/projects/5348ae65-b9b1-406d-b9d4-1f9139933a37` | organization-owned Common Space |
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
| Any OpenCloud user | Space-specific WebDAV URL | online network mount only |

Never point both the OpenCloud desktop client and Syncthing at the same local
directory. Pick one synchronization engine per local path.

For a VM/LXC path that must be immediately consistent with OpenCloud, mount
the Space through WebDAV. Native CephFS, NFS, and Proxmox bind mounts remain
useful for controlled Unix workflows, but OpenCloud 5.2 does not receive
remote CephFS-client changes through `inotify`; it assimilates them on its next
startup scan. Do not use a raw mount and OpenCloud concurrently for the same
active working set.

## Organization-owned Common Space

OpenCloud creates the `Common` Space before any NFS export is configured. Its
immutable Space ID determines the physical PosixFS path:

```text
/srv/user-files/projects/5348ae65-b9b1-406d-b9d4-1f9139933a37
content:/users/projects/5348ae65-b9b1-406d-b9d4-1f9139933a37
```

The same directory is exported as `10.200.0.209:/common`. This is one data
copy with two presentation and authorization planes:

- OpenCloud web, mobile, desktop, and WebDAV share the Space once with
  `opencloud-users` at `Can edit`; do not separately share it with the broader
  `standard-users` or `trusted-users` groups.
- Managed Unix VMs use NFS with the Kanidm `storage_common_rw` GID.
- LXCs receive a Proxmox host mount point; they do not mount NFS themselves.

The directory is setgid and has default ACLs for OpenCloud service UID/GID
`1000:1000` and the canonical Kanidm group. OpenCloud owns the personal Space
root as `1000:1000`; Kanidm UID/primary GID `1888405477` receives named access
and default ACL entries. OpenCloud users without a Kanidm POSIX identity can
use OpenCloud and WebDAV but cannot use NFS. Do not infer Unix access from
Google login or Authentik application membership.

Collaborative PosixFS assimilates external changes, but external writes bypass
OpenCloud upload-time checks. Do not perform bulk cross-Space moves, mass
deletion, symlink-based layouts, or recursive permission rewrites while
OpenCloud is running.

## Client instructions

### VM

Install the Kanidm Unix client, `ceph-common`, `acl`, and `attr`. Enroll the
path-scoped keyring as:

```text
/etc/ceph/ceph.client.sulibot-cloud.keyring
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

Direct VM clients must have bidirectional Ceph messenger routing to every
advertised monitor, MDS, and OSD address—not merely ICMP or a successful TCP
handshake. VLAN 200 therefore has a host-specific route for `fc00:20::/64`
through the VM's local PVE node: `fd00:200::1`, `::2`, or `::3`. The routed
Ceph messenger session, path-scoped mount, and canonical-UID write are part of
validation. Do not broaden CephX caps or expose an admin key to work around a
routing failure.

Mount the organization-owned Common Space separately at `/srv/common`:

```console
mount -t nfs4 -o vers=4.1,proto=tcp,hard \
  10.200.0.209:/common /srv/common
```

The user's supplemental `storage_common_rw` GID grants the filesystem access.
Root is intentionally squashed and may not list the directory.

For Debian, treat the Kanidm unixd package as an OS support gate. The
community Kanidm PPA currently publishes Debian 12 (`bookworm`) packages, not
Debian 13 (`trixie`) packages. Do not install an arbitrary mismatched binary,
fall back to a local account, or copy a UID from email. Either use the
supported Debian release, publish an internally tested package that matches
the Kanidm server, or keep the Debian 13 guest limited to non-interactive
numeric-ID storage validation until packaging is available. Do not offer
human PAM login there until NSS/PAM resolves the Kanidm account. The NixOS
client uses the repo-pinned Kanidm package and is the reference
identity-validation client.

### LXC

The container receives no Ceph key. Proxmox mounts `content` and passes only:

```text
/mnt/pve/content/users/sulibot/Cloud -> /home/sulibot/Cloud
/mnt/pve/content/users/projects/5348ae65-b9b1-406d-b9d4-1f9139933a37 -> /srv/common
```

The bind source must exist on every PVE node and the mount point must be marked
shared. The post-apply reconciler explicitly writes `mp0` and `mp1` because a
new container create can return with only the first provider `mount_point`
block applied. Validate both runtime mount points, Kanidm resolution, and
mapped ownership before enabling user write access. `vzdump` does not back up
bind-mounted content.

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
Kafka; it is not a direct watcher for a mounted CephFS tree. This stack does
not run that event pipeline, so it uses `inotifywait`. Inotify is real-time
only for writers using the same Kubernetes node-staged PVC. Syncthing therefore
reuses `user-storage-opencloud`, mounts `sulibot/Cloud` with `subPath`, and has
required pod affinity to OpenCloud. Independent Proxmox, NFS, and CephFS
clients are assimilated only by a subsequent OpenCloud startup scan.

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
4. Grant the user `opencloud-users` membership and complete one OpenCloud
   login so OpenCloud creates `/users/<name>/Cloud` and its Space metadata.
5. Apply the canonical-user access/default ACL without changing the Space
   owner or removing `user.oc.*` attributes.
6. Deploy `syncthing-<name>` with its own RBD config PVC, the shared OpenCloud
   file-data PVC, a user-specific `subPath`, and required OpenCloud pod affinity.
7. Authorize the personal and Common Spaces in OpenCloud.
8. Validate create, update, rename, and delete propagation from Syncthing and
   an OpenCloud client before enabling any independent raw mount.

## SLOs and alerts

- Alert when the Syncthing pod is unavailable for 15 minutes.
- Alert on out-of-sync items older than one hour while a peer is connected.
- Alert on CephFS near-full, MDS damage, or failed snapshots.
- Quarterly restore test for application state and user files.
- Review CephX caps and Syncthing device membership during user offboarding.

## Destructive reset

The original OpenCloud instance was declared disposable and its old PVC was
deleted without backup during this cutover. OpenCloud application state now
uses the new RBD PVC; the retained CephFS user tree is managed independently.
For a future reset, scale OpenCloud to zero, delete only its application-state
PVC, recreate the service, and validate the retained user tree before allowing
writers.
