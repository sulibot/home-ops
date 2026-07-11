# cluster-104 Bare-Metal Talos

Single-node Talos Kubernetes cluster on repurposed bare-metal hardware.

- Cluster name: `cluster-104`
- Cluster role: Home Assistant / home-control
- Cluster ID: `104`
- Node hostname: `talos01`
- Former role/name: `pve04`
- Recovery/bootstrap network: native/untagged `vlan10`
- Recovery IPs:
  - IPv4: `10.10.0.4`
  - IPv6: `fd00:10::4`
- Cluster network: tagged `vlan104`
- LAN/media attachment: tagged `vlan30`
- IoT/Matter attachment: tagged `vlan31`
- Cluster endpoint IPs:
  - IPv4: `10.104.0.4`
  - IPv6: `fd00:104::4`

Workflow:

1. `secrets/` generates or reuses Talos machine secrets.
2. `config/` renders Talos config for `cluster-104` and exports repo-local artifacts.
3. `apply/` applies the machine config to a Talos node in maintenance mode.
4. `bootstrap/` bootstraps the one-node Kubernetes cluster and writes kubeconfig.
5. `cilium-bootstrap/` installs Gateway API CRDs and Cilium so the node can become Ready.

Notes:

- This stack does not provision compute. `talos01` is the former `pve04` physical machine.
- VIP is intentionally disabled. The node IP is the Kubernetes endpoint.
- This is a bare-metal single-node profile. It intentionally does not inherit
  Proxmox SDN/vnet assumptions unless VM participation becomes a real
  requirement later.
- The cluster has its own Talos Image Factory schematic under `schematic/`.
  It excludes `qemu-guest-agent`; the shared artifact schematic can still be
  used by VM-oriented clusters.
- Keep `vlan10` native/untagged for recovery/bootstrap. The real cluster
  network is tagged `vlan104`. Home Assistant uses Multus/macvlan secondary
  attachments on tagged `vlan30` and `vlan31` for LAN discovery/control,
  without moving its default route off the cluster network.
- BGP follows the same local Cilium-to-BIRD pattern as cluster-101, but
  RouterOS peers directly with the bare-metal `talos01` node on `vlan104`
  because there is no Proxmox FRR layer in this cluster.
- Workloads are allowed on the control plane because this is a 1-node cluster.

## Addressing Alignment

Cluster numbering maps directly to the routed tenant networks:

| Cluster | Fabric | Nodes | Services | Pods | LoadBalancers | BGP loopbacks |
| --- | --- | --- | --- | --- | --- | --- |
| `cluster-101` | `vlan101` / `vnet101` | `10.101.0.0/24`, `fd00:101::/64` | `10.101.96.0/24`, `fd00:101:96::/108` | `10.101.224.0/20`, `fd00:101:224::/60` | `10.101.250.0/24`, `fd00:101:250::/112` | `10.101.254.0/24`, `fd00:101:fe::/64` |
| `cluster-102` | `vlan102` / `vnet102` | `10.102.0.0/24`, `fd00:102::/64` | `10.102.96.0/24`, `fd00:102:96::/108` | `10.102.224.0/20`, `fd00:102:224::/60` | `10.102.250.0/24`, `fd00:102:250::/112` | `10.102.254.0/24`, `fd00:102:fe::/64` |
| `cluster-103` | `vlan103` / `vnet103` | `10.103.0.0/24`, `fd00:103::/64` | `10.103.96.0/24`, `fd00:103:96::/108` | `10.103.224.0/20`, `fd00:103:224::/60` | `10.103.250.0/24`, `fd00:103:250::/112` | `10.103.254.0/24`, `fd00:103:fe::/64` |
| `cluster-104` | `vlan104` bare metal | `10.104.0.0/24`, `fd00:104::/64` | `10.104.96.0/24`, `fd00:104:96::/108` | `10.104.224.0/20`, `fd00:104:224::/60` | `10.104.250.0/24`, `fd00:104:250::/112` | `10.104.254.0/24`, `fd00:104:fe::/64` |

For `cluster-104`, `talos01` should eventually use:

- Node: `10.104.0.4`, `fd00:104::4`
- BGP loopback: `10.104.254.4`, `fd00:104:fe::4`

The physical port should keep native recovery while adding the cluster network:

| Port | Native/untagged | Tagged |
| --- | --- | --- |
| `talos01[ether5]` | `vlan10` recovery/PXE/bootstrap | `vlan104` cluster network, `vlan30` LAN/media, `vlan31` IoT/Matter |

## Outstanding Issues

- [x] Stage RouterOS L2 membership for `vlan104` on `talos01[ether5]` as tagged, while keeping native `vlan10`.
- [x] Stage RouterOS L3/DHCP/DNS/routing for `10.104.0.0/24` and `fd00:104::/64`, including cluster-104 endpoint records.
- [x] Apply the RouterOS `vlan104` changes live with targeted RouterOS CLI.
- [ ] Reconcile/import RouterOS Terraform state before using a full `terragrunt apply`; the current RouterOS plan wants to create the whole router.
- [ ] Add delegated GUA prefix mapping for `vnet104` if cluster-104 should receive public IPv6.
- [x] Decide whether cluster-104 should be a bare-metal routed VLAN only, or also have a Proxmox SDN `vnet104` peer for consistency with `cluster-101` through `cluster-103`: keep it bare-metal routed VLAN only for now.
- [x] Stage Talos node intent for `enp1s0.104` as the cluster network and native `enp1s0` as recovery.
- [x] Wipe/reinstall Talos so the Kubernetes endpoint, pod/service CIDRs, Cilium native routing CIDRs, and BGP identity all use cluster ID `104`.
- [x] Bootstrap Cilium on `cluster-104` with native routing CIDRs `10.104.0.0/16` and `fd00:104::/48`.
- [x] Apply cluster-104 Cilium BGP resources for `talos01`, local bird2 peering, and the `10.104.250.0/24` / `fd00:104:250::/112` LoadBalancer pool.
- [x] Apply the Home Assistant local-storage overlay directly to the cluster.
- [x] Bootstrap Flux on `cluster-104` and let it reconcile `kubernetes/clusters/cluster-104`.
- [x] Resolve the final recovery VLAN posture: keep `vlan10` native/untagged on `talos01[ether5]` while `vlan104` is tagged.
- [x] Remove `qemu-guest-agent` from the active Talos image by switching to the cluster-104 bare-metal schematic.
- [x] Run `bird2` as the Talos BGP extension without `qemu-guest-agent`.
- [x] Establish local Cilium-to-BIRD BGP peering on `::1`.
- [x] Establish RouterOS-to-`talos01` BGP peering for cluster-104 routes:
  - RouterOS connection: `CLUSTER104_TALOS01`
  - RouterOS local AS: `4200001000`
  - `talos01` remote AS: `4210104004`
  - RouterOS local address: `fd00:104::fffe`
  - `talos01` address: `fd00:104::4`
  - BFD: disabled for this direct bare-metal peer
- [x] Add `vlan31` as a tagged IoT/Matter attachment on `talos01[ether5]` and configure Talos `enp1s0.31` as `10.31.0.6` / `fd00:31::6`.
- [x] Add `vlan30` as a tagged LAN/media attachment on `talos01[ether5]` and configure Talos `enp1s0.30`.
- [x] Install Multus on cluster-104 and attach Home Assistant to `vlan30` and `vlan31` with static secondary addresses:
  - `10.30.0.251`, `fd00:30::251`
  - `10.31.0.251`, `fd00:31::251`
- [x] Migrate Home Assistant `/config`, secrets, and OIDC settings from the main cluster.
- [x] Move USB radio hardware to `talos01` and identify the stable SONOFF Zigbee path: `/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_20231007151738-if00`.
- [x] Expose Home Assistant through cluster-104 Cilium Gateways:
  - `gateway-internal`: `10.104.250.11`, `fd00:104:250::11`
  - `gateway-tunnel`: `10.104.250.12`, `fd00:104:250::12`
- [x] Move `hass*.sulibot.com` internal DNS ownership to cluster-104 ExternalDNS with TXT owner `cluster-104`.
- [x] Remove or redirect the main-cluster Home Assistant deployment after cutover.
- [x] Disable incomplete Google Assistant setup from the migrated Home Assistant config.
- [x] Trust cluster-104 Cilium Gateway proxy ranges in Home Assistant:
  - `10.104.224.0/20`
  - `fd00:104:224::/60`
- [x] Restore immediate Matter control by repointing the migrated Home Assistant Matter integration to `ws://matter-server.matter-server.svc.cluster.local:5580/ws`.
- [x] Move Matter server and its fabric data to cluster-104 so the old/main cluster is no longer in the Home Assistant control path. See [cluster-104 Matter server migration ticket](../../../../../docs/tickets/cluster-104-matter-server-migration.md).
- [x] Run OTBR on cluster-104 with the moved USB radio and point Home Assistant at `http://otbr.otbr.svc.cluster.local:8081`.
- [ ] Triage the remaining unavailable individual Matter bulb/button entities after the Matter server migration. The main Matter switch/group entities are online.
- [ ] Move the live `otbr-thread-dataset` secret into the repo secret workflow, without committing the Thread dataset in plaintext.
- [ ] Decide whether Home Assistant should keep direct `/dev/ttyACM0` mounts now that OTBR owns the radio, or remove those mounts and make OTBR the only radio owner.
- [ ] Add backup/restore coverage for the local `ha-data` user volume.
- [x] Reconcile/import the live RouterOS `CLUSTER104_TALOS01` BGP connection into Terraform state and remove the temporary broad static routes after BGP covered pod/LB reachability. See [cluster-104 routing ticket](../../../../../docs/tickets/cluster-104-routeros-routing-debt.md).
- [ ] Resolve the migrated Home Assistant `uv was not found` warning if custom integrations need that package manager at runtime.
