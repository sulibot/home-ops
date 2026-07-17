# Archived: vendored lae.proxmox role + collections snapshot

Archived 2026-07-13 during the refactor documented at
`.claude/plans/declarative-forging-volcano.md`.

`role/` is the upstream `lae.proxmox` Galaxy role
(https://github.com/lae/ansible-role-proxmox), vendored in-tree.
`collections/` is a committed snapshot of `community.general` that is no
longer needed now that collections are installed via
`ansible-galaxy collection install -r requirements.yml` instead of being
checked into git.

Only two call sites ever actually used the vendored role, both replaced:

- `ceph-only.yml` imported `lae.proxmox`'s `ceph.yml` tasks (pveceph
  init/mon/mgr) → replaced by `ansible/pve/roles/ceph_cluster_init`.
- `pve-accounts.yml` imported `lae.proxmox`'s `accounts.yml` tasks (PVE
  RBAC users/groups/ACLs) → replaced by `ansible/pve/roles/pve_accounts`,
  built on the `community.proxmox` collection (the maintained successor to
  `community.general`'s deprecated proxmox modules).

Kept here for reference while the two replacement roles are validated
against a real cluster build. Safe to delete once that's done.
