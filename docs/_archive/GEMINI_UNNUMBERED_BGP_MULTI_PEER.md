# Gemini Prompt: FRR Unnumbered BGP with Multiple Peers on Same Subnet

## Problem Statement

I have FRR 10.5.0 running on Proxmox hosts providing BGP routing for VMs on VXLAN/EVPN networks. I need **multiple VMs on the same Layer 2 segment to establish unnumbered BGP peering** with the Proxmox host, but I'm encountering a limitation.

## Current Setup

**Proxmox Side (Gateway):**
- FRR 10.5.0 in VRF `vrf_evpnz1`
- VXLAN interface `vnet101` with bridge (Layer 2 segment for multiple VMs)
- ASN: 4200001000
- Configuration: `neighbor vnet101 interface peer-group VNET_PEERS`
- Peer group: `neighbor VNET_PEERS remote-as external`

**VM Side:**
- Multiple VMs (VM-A and VM-B) connected to the same `vnet101` bridge
- Each VM: FRR 10.2/10.5.0
- VM-A ASN: 4210101006, IP: 10.0.101.6/24
- VM-B ASN: 4210101007, IP: 10.0.101.7/24
- Configuration: `neighbor eth0 interface remote-as 4200001000`
- Both using MP-BGP with `capability extended-nexthop`

## Current Behavior

**Only ONE VM can establish BGP peering at a time:**
- VM-B (first to connect): Session ESTABLISHED ✅
- VM-A (second attempt): Session stuck in ACTIVE/IDLE ❌

Both VMs are on the same Layer 2 segment (`vnet101` bridge) attempting unnumbered BGP peering with the same Proxmox interface.

## Research Findings

According to [FRR GitHub Issue #8689](https://github.com/FRRouting/frr/issues/8689):

> "This connection type is meant for point-to-point connections. **If you are on an ethernet segment and attempt to use this with more than one BGP neighbor, only one neighbor will come up**, due to how this feature works."

Additional context from [Issue #9465](https://github.com/FRRouting/frr/issues/9465):
> "The unnumbered config only processes/accepts the first RA received on the interface, and when there are multiple hosts/RAs on any given interface, this doesn't work."

## Configuration Files

**Proxmox FRR Config:** `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

Key section (lines 200-210):
```
router bgp 4200001000 vrf vrf_evpnz1
  bgp router-id 10.0.10.1
  no bgp default ipv4-unicast
  timers bgp 10 30

  neighbor VNET_PEERS peer-group
  neighbor VNET_PEERS remote-as external
  neighbor VNET_PEERS capability extended-nexthop
  neighbor VNET_PEERS timers 10 30
  neighbor VNET_PEERS ttl-security hops 1
  neighbor VNET_PEERS bfd
  neighbor vnet101 interface peer-group VNET_PEERS  # Only supports ONE peer!
```

**VM FRR Config:** Test VMs use similar config
```
router bgp 4210101006  # (or 4210101007 for VM-B)
  bgp router-id 10.255.101.6  # (or .7 for VM-B)
  no bgp default ipv4-unicast
  neighbor eth0 interface remote-as 4200001000
  neighbor eth0 capability extended-nexthop
  neighbor eth0 timers 10 30
  neighbor eth0 ttl-security hops 1
  neighbor eth0 bfd
```

## Questions for Gemini

### 1. Workaround Options

Given the limitation of interface-based unnumbered BGP, what are the **recommended approaches** for enabling multiple VMs on the same Layer 2 segment to peer with FRR?

**Option A: Explicit Link-Local Neighbors**
```
# Instead of: neighbor vnet101 interface peer-group VNET_PEERS
# Use explicit link-local addresses:
neighbor fe80::be24:11ff:fe2f:c6a3 interface vnet101 peer-group VNET_PEERS  # VM-A
neighbor fe80::be24:11ff:fe45:b5af interface vnet101 peer-group VNET_PEERS  # VM-B
```

**Questions:**
- Will this work with VRF contexts in FRR 10.5.0?
- Do we still get the benefits of unnumbered peering (no IPv4/IPv6 GUA needed)?
- How does this interact with `remote-as external`?

**Option B: BGP Listen Range**
```
# Instead of interface-based peering:
bgp listen limit 256
bgp listen range 10.0.101.0/24 peer-group VNET_PEERS
bgp listen range fd00:101::/64 peer-group VNET_PEERS
```

**Questions:**
- Does `bgp listen range` work in VRF contexts with `net.ipv4.tcp_l3mdev_accept=1`?
- Is this still considered "unnumbered" if we use IPv6 link-local for the actual peering?
- FRR Issue #2906 mentioned problems with `bgp listen range` in VRF - is this fixed in 10.5.0?

**Option C: Per-VM Tap/Veth Interfaces**
- Create individual tap/veth pairs per VM instead of shared bridge
- Each gets its own `vnet101-vm-a`, `vnet101-vm-b` interface on Proxmox

**Questions:**
- Would this break VXLAN/EVPN forwarding between VMs?
- Is this compatible with Proxmox SDN?

### 2. Production Use Case Validation

**My actual use case:** Talos Kubernetes nodes (3-5 VMs per cluster) on the same VXLAN vnet need to:
1. Peer with Proxmox via unnumbered BGP (prefer link-local only)
2. Advertise their pod/service loopback ranges to Proxmox
3. Receive default routes (0.0.0.0/0 and ::/0) from Proxmox
4. Use MP-BGP for both IPv4 and IPv6

**Questions:**
- What's the **best practice** architecture for this scenario?
- Should each Talos node get a dedicated vnet (vnet101-node1, vnet101-node2)?
- Or is Option A (explicit link-local neighbors) the standard approach?

### 3. Dynamic Neighbor Discovery

**Ideal scenario:** VMs come and go (Kubernetes autoscaling), so I want:
- Proxmox to **automatically accept** BGP sessions from any VM on vnet101
- VMs identified by ASN range (4210000000-4210999999)
- No manual configuration per VM

**Questions:**
- Is there a way to achieve this with unnumbered BGP in FRR?
- Would Router Advertisement (RA) based peer discovery work here?
- Should I abandon unnumbered and use traditional BGP with IPv6 GUA addresses?

### 4. Configuration Verification

Based on my repository code (you have access), please review:

1. **Is my current Proxmox FRR template optimal?**
   - File: `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`
   - Lines 195-245 (VRF BGP config)

2. **Is the Talos FRR template compatible?**
   - File: `terraform/infra/modules/talos_config/frr.conf.j2`
   - Will Talos nodes using this template successfully peer with Proxmox?

3. **Are there any FRR 10.5.0-specific features** I should leverage for this use case?

## Expected Outcome

I need a solution that:
1. ✅ Supports **multiple VMs on same vnet** peering with Proxmox
2. ✅ Uses **unnumbered/link-local peering** (no IPv4 addressing required, IPv6 link-local only)
3. ✅ Works in **VRF context** (`vrf_evpnz1`)
4. ✅ Supports **MP-BGP** (both IPv4 and IPv6 address families)
5. ✅ Allows **dynamic peer discovery** (no manual per-VM config on Proxmox)
6. ✅ Production-ready for Kubernetes workloads

## Additional Context

- Kernel parameter `net.ipv4.tcp_l3mdev_accept=1` is set
- VXLAN MTU: 1450
- EVPN Type-5 routes advertised between Proxmox hosts
- Currently one test VM works perfectly (MP-BGP established, default routes received)

## Request

Please provide:
1. **Recommended solution** with specific FRR configuration snippets
2. **Explanation** of why this approach works around the limitation
3. **Any caveats or trade-offs** I should be aware of
4. **Validation** that the solution works with my existing VXLAN/EVPN setup

---

## References

- [FRR BGP Documentation](https://docs.frrouting.org/en/latest/bgp.html)
- [FRR Issue #8689 - BGP unnumbered multiple peers limitation](https://github.com/FRRouting/frr/issues/8689)
- [FRR Issue #9465 - Per-interface BGP listen for IPv6 link-local peers](https://github.com/FRRouting/frr/issues/9465)
- [FRR Issue #2906 - BGP dynamic listen under VRF](https://github.com/FRRouting/frr/issues/2906)
- [Proxmox BGP+EVPN+VXLAN Blog Post](https://blog.widodh.nl/2022/03/proxmox-with-bgpevpnvxlan/)
