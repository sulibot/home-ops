# CephFS NFS gateway

## Service contract

`nfsgw01` on `pve01` and `nfsgw02` on `pve02` expose the canonical
`content:/users/sulibot/Cloud` CephFS directory as NFSv4 pseudo-path
`/shared`. Clients use the floating endpoint `10.200.0.209`; they do not mount
either gateway's node address.

The gateways are active/passive as one logical NFS server. Keepalived starts
NFS-Ganesha only on the VIP owner; the standby has the packages, Ceph
credentials, and configuration but no running Ganesha daemon. Both nodes use
the same stable server identity and `rados_ng` recovery record in the
`nfs-ganesha` RADOS pool, so client state follows the service. The file data
remains in CephFS and is never copied into an LXC root disk.

Each gateway has a specific route for the Ceph public messenger subnet through
its local PVE node. This keeps Ceph request and response traffic symmetric;
routing those sessions through the tenant default gateway causes the local PVE
reply path to bypass that gateway.

The service intentionally supports NFSv4.1 and 4.2 over TCP with AUTH_SYS.
Root is squashed. Kanidm remains the authority for stable numeric UID/GID
allocation; NFS transports those numeric IDs and does not authenticate a
person with Google or Authentik.

## Security boundaries

- `client.nfs-shared` is limited by MDS caps to
  `/users/sulibot/Cloud` in the `content` filesystem.
- `client.nfs-recovery` can write only the `nfs-ganesha` recovery pool.
- Client access is limited to tenant 200 (`10.200.0.0/24` and
  `fd00:200::/64`).
- The LXCs are privileged only because Keepalived must add and remove the VIP.
  They are single-purpose infrastructure guests and receive no host CephFS
  bind mount.
- CephX keys are streamed from `pve01` by `configure-ceph.sh`; they are not
  committed and do not enter Terraform state.

## Deploy or reconcile

From `terraform/infra/live/services/nfs-gateway`:

```console
terragrunt apply
./configure-ceph.sh
./validate.sh
```

`terragrunt apply` creates the Debian 13 LXCs and installs Ganesha and
Keepalived. `configure-ceph.sh` creates/reconciles the Ceph pool and identities,
streams credentials to both gateways, validates the Ganesha configuration, and
starts the services. `validate.sh` uses `debfs-lxc01` (`10.200.0.206`) as its
default clean NFS client.

## Client setup

Install the NFS client:

```console
apt-get install nfs-common
install -d -m 0750 /home/sulibot/Cloud
mount -t nfs4 -o vers=4.1,proto=tcp,hard,timeo=600,retrans=2 \
  10.200.0.209:/shared /home/sulibot/Cloud
```

For a persistent Debian mount:

```fstab
10.200.0.209:/shared /home/sulibot/Cloud nfs4 vers=4.1,proto=tcp,hard,_netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=600,timeo=600,retrans=2 0 0
```

For the IPv6 VIP, bracket the literal address and select the IPv6 transport:

```console
mount -t nfs4 -o vers=4.1,proto=tcp6,hard \
  '[fd00:200::209]:/shared' /home/sulibot/Cloud
```

Use the same mount declaration in a VM. A Proxmox LXC that mounts NFS itself
must be allowed to perform NFS mounts; prefer a VM for untrusted workloads.
For a trusted LXC, enable the `mount=nfs` feature in its PVE configuration and
keep the mount scoped to the required export.

The local account must resolve to the canonical Kanidm UID/GID before writing.
Check with:

```console
id sulibot
stat -c '%u:%g %n' /home/sulibot/Cloud
```

The expected current owner is `1000:1000`. A Google or Authentik login may
establish a web identity, but it does not replace the Kanidm POSIX identity
used by NFS.

## Operations and failure handling

Check the endpoint and both nodes:

```console
mount -t nfs4 -o vers=4.1,proto=tcp 10.200.0.209:/shared /mnt/test
ssh root@10.200.0.207 systemctl status nfs-ganesha keepalived
ssh root@10.200.0.208 systemctl status nfs-ganesha keepalived
```

`showmount` is not an export test for this NFSv4-only service because the
NFSv3 mount protocol is disabled.

Find the VIP owner:

```console
for host in 10.200.0.207 10.200.0.208; do
  ssh root@"$host" "ip -4 -brief address show dev eth0 | grep 10.200.0.209" &&
    echo "VIP owner: $host"
done
```

During maintenance, stop Keepalived on the current owner; its state callback
force-stops Ganesha and the peer starts Ganesha when it acquires the VIP. The
forced stop avoids a Debian Ganesha 6.5 shutdown deadlock observed during live
validation and exercises the same recovery path as abrupt host loss. Do not
manually run Ganesha on both nodes. NFS clients use hard mounts and wait
through session recovery instead of returning silent I/O errors.

If a Ganesha health failure demotes a gateway, it creates
`/run/nfs-gateway-inhibit` so the failed node cannot immediately preempt the
healthy peer. After correcting the cause, clear the marker; the preferred node
will preempt after three successful health checks:

```console
ssh root@10.200.0.207 rm -f /run/nfs-gateway-inhibit
```

Run `./validate-failover.sh` from the service directory during a maintenance
window to exercise Ganesha failure, VIP movement, I/O through an existing
mount, and primary recovery.

Do not delete `nfs-ganesha` or either CephX identity during routine rebuilds.
The LXC root disks are disposable; the CephFS data and RADOS recovery pool are
not.
