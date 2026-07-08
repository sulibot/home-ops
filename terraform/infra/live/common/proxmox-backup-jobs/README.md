# Proxmox Backup Jobs

This stack manages Proxmox cluster backup jobs through BPG.

The initial job backs up the current non-template guests daily to the existing
`config` CephFS storage, which currently has backup content enabled and enough
free space for a first Proxmox-level safety net.

The job uses an explicit `vmid` list instead of `all = true` so template guests
and future test guests are not pulled into scheduled backups accidentally.

Kubernetes PVC/application backup policy remains in Kubernetes GitOps/VolSync;
this stack is only for Proxmox VM/LXC backups.

## Restore-Path Test Result

On July 7, 2026, stopped VM `200252` (`haos`) was backed up manually with the
same storage/compression mode:

```sh
vzdump 200252 --storage config --mode snapshot --compress zstd
```

The archive was created at:

```text
/mnt/pve/config/dump/vzdump-qemu-200252-2026_07_07-16_20_43.vma.zst
```

Validation performed:

- `vma verify` read the full archive successfully.
- The archive was restored to temporary VMID `920252` on `local-zfs`.
- The restored VM config was readable.
- Temporary VMID `920252` was destroyed and purged.

Stale guests discovered during backup testing and deleted on July 7, 2026:

- `100`: missing `resources:snippets/debian13-template-user-data.yaml`
- `101`: missing `resources:snippets/debian13-template-user-data.yaml`
- `200033`: local raw rootfs backup validation failure
- `200064`: missing `resources:snippets/debian13-template-user-data.yaml`
- `200101`: missing `rpool/data/subvol-200101-disk-0`

After deleting those stale guests and removing deleted VM `200252` from the
inventory, the scheduled backup job covers every remaining non-template VM/LXC
in the cluster and excludes only template `9000`.
