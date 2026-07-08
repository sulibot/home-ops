# Proxmox Storage

This stack adopts only storage types currently supported by BPG resources in
this cluster:

- `local` as directory storage
- `local-zfs` as ZFS pool storage

Current live `cephfs` and `rbd` storage definitions are deliberately not modeled
here because the current BPG resource list does not include first-class CephFS or
RBD storage resources.

Live Proxmox storage definitions outside current BPG coverage:

- `resources` (`cephfs`, shared, `/mnt/pve/resources`)
- `content` (`cephfs`, shared, `/mnt/pve/content`)
- `config` (`cephfs`, shared, `/mnt/pve/config`)
- `rbd-vm` (`rbd`, shared, pool `rbd-vm`)

Treat those as live Proxmox/Ceph storage definitions, with Ceph pools managed in
`terraform/infra/live/common/2-ceph-pools` where supported and OSD/CRUSH/DB/WAL
maintained by Ansible.
