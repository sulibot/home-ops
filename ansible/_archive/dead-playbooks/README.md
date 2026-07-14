# Archived: dead playbooks

Archived 2026-07-13 during the lae.proxmox refactor
(`.claude/plans/declarative-forging-volcano.md`).

- `provision_fixed_osds_playbook.yml`: references a `provision_fixed_osds`
  role that does not exist anywhere in the repo (never committed, or
  removed at some point without removing this playbook), and its
  `vars_files` path was already broken independent of that
  (`../host_vars/...` pointed at a directory that was never actually
  `ansible/lae.proxmox/host_vars/` - host_vars lived under `inventory/`).
  Functionally superseded by `ansible/pve/roles/ceph_osd_create`, which
  does the same fixed-OSD-ID-from-host_vars provisioning and is actually
  wired up and working.
