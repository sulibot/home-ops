# Archived: unreferenced Ceph reference material

Archived 2026-07-14, found while auditing `ansible/pve/files/` for cruft
during the lae.proxmox refactor. None of these were referenced by any
role or playbook - confirmed via `grep -rl` across `ansible/pve/`.

- `remove_osd.sh` - 0 bytes, empty file.
- `crushmap.txt` / `crushmap_base.txt` - raw `ceph osd getcrushmap`
  decompiled dumps, point-in-time snapshots. CRUSH map management is now
  Terraform-owned (`terraform/infra/live/common/2-ceph-pools`) or driven
  by live cluster state, not these static files.
- `crushmap_gold.txt` / `crushmap_gold_old.txt` - two more CRUSH map
  snapshots; `_gold_old` differs from `_gold` in one EC rule definition
  (`ec_4_2_by_drive_host` id 3 -> `ec_4_2_host_then_drive` id 4), and is
  explicitly marked superseded by its own filename.
- `cephfs_content_setup.md` - an earlier draft CephFS pool-naming plan
  (`content_meta`/`content_default`/`content_ec`) that doesn't match the
  naming actually used elsewhere in this repo's history
  (`content_metadata`/`content_data`/`content_data_ec`) - superseded
  planning material, not current design.

`ansible/pve/files/ceph-layout.md` was reviewed at the same time and kept
in place - it's current, accurate, and documents the still-active
`ceph-layout-validate.yml` / `ceph-osd-reconcile.yml` /
`ceph-optane-db-migrate.yml` playbooks (only its one `cd
ansible/lae.proxmox` path reference was stale, fixed to `ansible/pve`).
