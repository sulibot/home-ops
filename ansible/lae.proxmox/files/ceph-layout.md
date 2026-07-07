# Proxmox Ceph Layout

`inventory/host_vars/pve0*.yml` is the source of truth for local OSD layout.

Use `ceph_osds` as the canonical schema:

- `osd_id`: fixed Ceph OSD id
- `data_device`: by-id partition used for the OSD block device
- `db_device`: Optane LVM logical volume intended for BlueStore DB
- `class`: CRUSH class
- `drive_bucket`: CRUSH drive bucket for dual-actuator HDDs
- `expected_bluefs_db`: whether live metadata should show a dedicated DB device

The dual-actuator HDD model is `root -> host -> drive -> osd`; both OSDs from the
same physical disk stay under the same `drive-*` bucket.

## Tool Ownership

Ansible owns the physical Ceph substrate:

- disk partitioning
- Optane LVM DB/WAL targets
- `ceph-volume` OSD create/recreate/migrate workflows
- CRUSH `drive-*` buckets for dual-actuator HDDs
- validation of live OSD metadata against `ceph_osds`

Terraform owns only Proxmox API-level Ceph pool declarations through
`terraform/infra/live/common/2-ceph-pools`, and only after each live pool is
imported and explicitly marked `managed = true`.

## Validation

Read-only layout audit:

```bash
cd ansible/lae.proxmox
ansible-playbook playbooks/ceph-layout-validate.yml
```

Read-only OSD reconciliation report:

```bash
ansible-playbook playbooks/ceph-osd-reconcile.yml
```

Enforce DB attachment once migration is complete:

```bash
ansible-playbook playbooks/ceph-layout-validate.yml -e ceph_layout_enforce_db=true
```

## Optane DB Migration

The migration playbook is dry-run/reporting by default:

```bash
ansible-playbook playbooks/ceph-optane-db-migrate.yml
```

It refuses to run unless all PGs are active+clean and all OSDs are up/in.

Execute one host at a time with an explicit limit after the cluster is healthy:

```bash
ansible-playbook playbooks/ceph-optane-db-migrate.yml \
  --limit pve01 \
  -e ceph_optane_db_migrate_execute=true
```

Do not run the migration while `pve03` has SATA/ATA errors or any OSD is down.
