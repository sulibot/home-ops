# Archived: roles/site

Archived 2026-07-13 during the lae.proxmox refactor
(`.claude/plans/declarative-forging-volcano.md`).

`tasks/main.yml` embeds a `hosts:`/`roles:` play block *inside a tasks
file*, which is invalid Ansible — a tasks file must be a flat list of tasks,
not a play. This could never have executed as written. It was never called
from any playbook.

The underlying idea — skip Ceph OSDs that already exist in the cluster
before attempting to create them — was reimplemented as real, executable
tasks in `ansible/pve/roles/ceph_cluster_init`. This directory is kept only
for reference; safe to delete once that replacement has been validated
against a real build.
