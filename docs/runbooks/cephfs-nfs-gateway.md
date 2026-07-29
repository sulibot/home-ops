# CephFS NFS gateway

## Service contract

`nfsgw01` on `pve01` and `nfsgw02` on `pve02` expose two canonical CephFS
directories through one NFSv4 endpoint:

- `/shared`: `content:/users/sulibot/Cloud`, the existing personal cloud tree.
- `/common`: `content:/users/projects/5348ae65-b9b1-406d-b9d4-1f9139933a37`, the
  organization-owned OpenCloud Common Space.

Clients use the floating endpoint `10.200.0.209`; they do not mount either
gateway's node address.

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
- `client.nfs-common` is limited to the immutable OpenCloud Common Space path.
- `client.nfs-recovery` can write only the `nfs-ganesha` recovery pool.
- Client access is limited to tenant 200 (`10.200.0.0/24` and
  `fd00:200::/64`).
- The export root grants other users execute-only traversal (effective mode
  `2771` after the ACL mask): the anonymous identity created by
  `Root_Squash` receives traverse-only access required for NFSv4 mount
  negotiation. OpenCloud owns the personal Space root as `1000:1000`;
  Kanidm UID/primary GID `1888405477` receives named access/default ACLs.
- The LXCs are privileged only because Keepalived must add and remove the VIP.
  They are single-purpose infrastructure guests and receive no host CephFS
  bind mount.
- CephX keys are streamed from `pve01` by `configure-ceph.sh`; they are not
  committed and do not enter Terraform state.

## Deploy or reconcile

From `terraform/infra/live/services/nfs-gateway`:

```console
export COMMON_SPACE_ID=5348ae65-b9b1-406d-b9d4-1f9139933a37
export COMMON_GID=1965604563
export USER_UID=1888405477
export USER_GID=1888405477
terragrunt apply
./configure-ceph.sh
./configure-client-monitoring.sh
./validate.sh
```

`terragrunt apply` creates the Debian 13 LXCs and installs Ganesha and
Keepalived. `configure-ceph.sh` creates/reconciles the Ceph pool and identities,
streams credentials to both gateways, validates the Ganesha configuration, and
starts the services. `validate.sh` uses `debfs-vm01` (`10.200.0.205`) as its
default clean NFS client. `configure-client-monitoring.sh` idempotently
reconciles the node_exporter and semantic probe on that VM without taking
ownership of the VM lifecycle.

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

For the organization-owned Common Space:

```fstab
10.200.0.209:/common /srv/common nfs4 vers=4.1,proto=tcp,hard,_netdev,nofail,x-systemd.automount,x-systemd.idle-timeout=600,timeo=600,retrans=2 0 0
```

For the IPv6 VIP, bracket the literal address and select the IPv6 transport:

```console
mount -t nfs4 -o vers=4.1,proto=tcp6,hard \
  '[fd00:200::209]:/shared' /home/sulibot/Cloud
```

Use the same mount declaration in a VM. On the current Proxmox/kernel release,
even a privileged LXC with `mount=nfs` and a matching AppArmor rule receives
`EPERM` from the kernel NFS mount operation. Do not make the container
unconfined to bypass this. Mount CephFS or NFS on the PVE host and pass only
the required directory into the LXC as a Proxmox mount point. `debfs-lxc01`
uses this host-managed, path-scoped model.

The local account must resolve to the canonical Kanidm UID/GID before writing.
Check with:

```console
id sulibot
stat -c '%u:%g %n' /home/sulibot/Cloud
```

The personal Space root owner is OpenCloud UID/GID `1000:1000`; the canonical
Kanidm UID/GID `1888405477:1888405477` is an ACL principal. NFS-created files
use canonical owner UID `1888405477` and inherit OpenCloud group `1000` from
the setgid Space root. The Common Space uses setgid and default ACLs for
OpenCloud UID/GID 1000 and Kanidm group
`storage_common_rw`. A Google or Authentik login may establish a web identity,
but it does not replace the Kanidm POSIX identity used by NFS.

OpenCloud's current `inotifywait` watcher does not receive changes made by
this independent Ganesha CephFS client. NFS writes are assimilated during the
next OpenCloud startup scan, not in real time. Use the Space's WebDAV endpoint
when a VM/LXC needs immediate OpenCloud consistency, and do not concurrently
edit the same active working set through raw NFS and OpenCloud.

The current `storage_common_rw` GID is `1965604563`. Verify the live value with
`kanidm group posix show storage_common_rw` before changing ACLs; the name is
canonical and the numeric value is recorded here for incident diagnosis.

For the validation VMs, route `fc00:20::/64` through the VM's local PVE node
before mounting native CephFS. VLAN 200's general gateway permits ICMP and the
initial TCP handshake but produces an asymmetric Ceph messenger session.
`nixfs-vm01` on `pve01` uses `fd00:200::1`; `debfs-vm01` on `pve03` uses
`fd00:200::3`. Confirm `ceph status --name client.sulibot-cloud` succeeds
before diagnosing CephX caps.

The LXC post-apply hook reconciles both `mp0` and `mp1`. If `/srv/common` is
missing after a fresh create, run `../reconcile-lxc-bind-mounts.sh` with the
node, VMID, both source/target pairs, and the canonical UID/GID. Do not accept
a clean OpenTofu plan as sufficient evidence; check `pct config` and the
runtime mount inside the container.

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

## Monitoring and alert response

The full service objectives, alert policy, error-budget policy, and review
cadence are in `docs/nfs-gateway-monitoring-plan.md`. The Grafana dashboard is
`SRE / NFS Gateway` in the `storage` folder.

Prometheus scrapes node_exporter on both gateways and `debfs-vm01`. Check the
local collectors:

```console
ssh root@10.200.0.207 systemctl status \
  prometheus-node-exporter nfs-gateway-metrics.timer
ssh root@10.200.0.208 systemctl status \
  prometheus-node-exporter nfs-gateway-metrics.timer
ssh root@10.200.0.205 systemctl status \
  prometheus-node-exporter nfs-client-probe.timer
curl -fsS http://10.200.0.207:9100/metrics | grep homeops_nfs_gateway
curl -fsS http://10.200.0.205:9100/metrics | grep homeops_nfs_client_probe
```

For `NFSSharedEndpointUnavailable`, start with the current client symptom and
then identify the service owner:

```console
ssh root@10.200.0.205 systemctl status nfs-client-probe.service
ssh root@10.200.0.205 journalctl -u nfs-client-probe.service -n 50 --no-pager
for host in 10.200.0.207 10.200.0.208; do
  ssh root@"$host" \
    'hostname; ip -brief address show dev eth0; systemctl is-active keepalived nfs-ganesha'
done
```

If exactly one node owns both VIPs and Ganesha is active there, inspect the
export and Ceph dependency:

```console
ssh root@10.200.0.207 \
  'busctl call org.ganesha.nfsd /org/ganesha/nfsd/ExportMgr \
    org.ganesha.nfsd.exportmgr ShowExports'
ssh root@pve01 ceph health detail
ssh root@pve01 ceph fs status content
```

For `NFSGatewayUnsafeHAState`, do not start Ganesha manually. Stop Keepalived
on the nonpreferred or unhealthy node, confirm one owner, and use
`configure-ceph.sh` to reconcile the logical service. Clear
`/run/nfs-gateway-inhibit` only after its underlying failure is understood and
the gateway metrics are healthy.
