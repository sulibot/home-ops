# Proxmox Ceph Pools

This stack is the Terraform boundary for Proxmox/Ceph pool objects managed through
the `bpg/proxmox` provider.

This stack uses the shared latest pre-1.0 `bpg/proxmox` provider constraint
because `proxmox_ceph_pool` requires a newer provider than the older 0.98-only
pin previously used by some stacks.

It intentionally does not manage:

- physical disks or partitions
- `ceph-volume`
- BlueStore DB/WAL placement or migration
- OSD destroy/recreate workflows
- CRUSH `root -> host -> drive -> osd` topology

Those stay in `ansible/lae.proxmox` because they require node-local commands,
health gates, and one-at-a-time maintenance sequencing.

## Adoption Workflow

1. Keep a pool entry at `managed = false` in
   `terraform/infra/live/common/proxmox-ceph-pools.hcl`.
2. Confirm the live pool settings with `ceph osd pool get`/`ceph osd pool ls detail`.
3. Flip exactly one pool to `managed = true`.
4. Import the existing pool:

   ```sh
   terragrunt import 'proxmox_ceph_pool.this["rbd-vm"]' pve01/rbd-vm
   ```

5. Run `terragrunt plan` and make the catalog match live state before applying.

Do not enable management for EC pools or CephFS metadata/data pools until a plan
has been reviewed against the live cluster.
