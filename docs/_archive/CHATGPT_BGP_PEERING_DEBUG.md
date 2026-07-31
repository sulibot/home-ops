# BGP Peering Troubleshooting - ChatGPT Prompt

## Problem Statement

I'm troubleshooting BGP peering between VMs and a Proxmox VRF using FRR. VMs are sending BGP messages but the Proxmox VRF is receiving zero messages. The passive interface-based peering on `vrf_evpnz1` doesn't seem to be picking up connections from VMs on the enslaved `vnet101` interface.

## Network Topology

```
┌─────────────────────────────────────────────────────────┐
│ Proxmox Host (pve01)                                    │
│                                                         │
│  ┌─────────────────────────────────────────┐           │
│  │ VRF: vrf_evpnz1 (ASN 4200001000)        │           │
│  │ - FRR 10.5.0                            │           │
│  │ - Passive BGP listener                  │           │
│  │ - Status: Idle, MsgRcvd: 0, MsgSent: 0  │           │
│  └─────────────────────────────────────────┘           │
│                      │                                  │
│                      │ (enslaved)                       │
│                      ▼                                  │
│  ┌─────────────────────────────────────────┐           │
│  │ vnet101 (VXLAN/EVPN SDN interface)      │           │
│  │ - IPv4: 10.0.101.254/24                 │           │
│  │ - IPv6: fd00:101::ffff/64               │           │
│  │ - VXLAN ID: 10101                       │           │
│  └─────────────────────────────────────────┘           │
│                      │                                  │
└──────────────────────┼──────────────────────────────────┘
                       │ (VXLAN tunnel)
                       │
                       ▼
         ┌─────────────────────────────────┐
         │ debian-test-1 VM                │
         │ - Interface: eth0               │
         │ - IPv4: 10.0.101.6/24           │
         │ - IPv6: fd00:101::6/64          │
         │ - FRR 10.2                      │
         │ - ASN: 4210101006               │
         │ - Status: Idle                  │
         │ - MsgRcvd: 10, MsgSent: 25      │
         │ - Active BGP peering            │
         └─────────────────────────────────┘
```

## Proxmox FRR Configuration

**File Reference:** `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

Key sections:
```
frr version 10.5.0
hostname pve01
vrf vrf_evpnz1
 vni 4096
 exit-vrf
!
router bgp 4200001000 vrf vrf_evpnz1
 bgp router-id 10.0.10.1
 no bgp default ipv4-unicast
 bgp graceful-restart
 !
 neighbor TALOS_PEERS peer-group
 neighbor TALOS_PEERS remote-as 4210000000-4210999999  # ASN range for cluster nodes
 neighbor TALOS_PEERS capability extended-nexthop
 neighbor TALOS_PEERS timers 10 30
 neighbor TALOS_PEERS ttl-security hops 1
 !
 neighbor vrf_evpnz1 interface peer-group TALOS_PEERS  # Passive listener on VRF
 !
 address-family ipv4 unicast
  neighbor TALOS_PEERS activate
  neighbor TALOS_PEERS route-map IMPORT-LOOPBACKS-v4 in
  neighbor TALOS_PEERS route-map EXPORT-DEFAULT-v4 out
 exit-address-family
 !
 address-family ipv6 unicast
  neighbor TALOS_PEERS activate
  neighbor TALOS_PEERS route-map IMPORT-LOOPBACKS-v6 in
  neighbor TALOS_PEERS route-map EXPORT-DEFAULT-v6 out
 exit-address-family
exit
```

## Test VM FRR Configuration

**Actual config on debian-test-1:**

```
frr version 10.2
hostname debian-test-1
log syslog informational
service integrated-vtysh-config
!
router bgp 4210101006
 bgp router-id 10.0.101.6
 no bgp default ipv4-unicast
 bgp graceful-restart
 timers bgp 10 30
 !
 neighbor eth0 interface remote-as 4200001000  # Active peering to Proxmox
 neighbor eth0 description "Proxmox SDN Gateway"
 neighbor eth0 capability extended-nexthop
 neighbor eth0 timers 10 30
 neighbor eth0 ttl-security hops 1
 !
 address-family ipv4 unicast
  redistribute connected route-map ADVERTISE-LOOPBACKS
  neighbor eth0 activate
  neighbor eth0 route-map IMPORT-DEFAULT-v4 in
  neighbor eth0 route-map ADVERTISE-LOOPBACKS out
 exit-address-family
 !
 address-family ipv6 unicast
  redistribute connected route-map ADVERTISE-LOOPBACKS-V6
  neighbor eth0 activate
  neighbor eth0 route-map IMPORT-DEFAULT-v6 in
  neighbor eth0 route-map ADVERTISE-LOOPBACKS-V6 out
 exit-address-family
exit
```

**This config is templated from:** `terraform/infra/modules/talos_config/frr.conf.j2`

## Observed Behavior

**From debian-test-1:**
```bash
# vtysh -c "show bgp summary"
IPv4 Unicast Summary (VRF default):
Neighbor        V         AS   MsgRcvd   MsgSent   Up/Down State/PfxRcd
eth0            4 4200001000        10        25  00:08:38 Idle

IPv6 Unicast Summary (VRF default):
Neighbor        V         AS   MsgRcvd   MsgSent   Up/Down State/PfxRcd
eth0            4 4200001000        10        25  00:08:38 Idle
```

**From pve01 (Proxmox):**
```bash
# vtysh -c "show bgp vrf vrf_evpnz1 summary"
IPv4 Unicast Summary (VRF vrf_evpnz1):
Neighbor        V         AS   MsgRcvd   MsgSent   Up/Down State/PfxRcd
vrf_evpnz1      4 4210000000         0         0    never Idle

IPv6 Unicast Summary (VRF vrf_evpnz1):
Neighbor        V         AS   MsgRcvd   MsgSent   Up/Down State/PfxRcd
vrf_evpnz1      4 4210000000         0         0    never Idle
```

**Key observation:** Test VM is sending 25 messages, Proxmox VRF is receiving 0 messages.

## Network Verification

**VM can reach Proxmox:**
```bash
root@debian-test-1:~# ping -c 2 10.0.101.254
PING 10.0.101.254 (10.0.101.254) 56(84) bytes of data.
64 bytes from 10.0.101.254: icmp_seq=1 ttl=64 time=0.234 ms
64 bytes from 10.0.101.254: icmp_seq=2 ttl=64 time=0.201 ms

root@debian-test-1:~# ping6 -c 2 fd00:101::ffff
PING fd00:101::ffff(fd00:101::ffff) 56 data bytes
64 bytes from fd00:101::ffff: icmp_seq=1 ttl=64 time=0.287 ms
64 bytes from fd00:101::ffff: icmp_seq=2 ttl=64 time=0.223 ms
```

**VM interface config:**
```bash
root@debian-test-1:~# ip addr show eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450
    inet 10.0.101.6/24 scope global eth0
    inet6 fd00:101::6/64 scope global
    inet6 fe80::bc24:11ff:fecb:f2a0/64 scope link
```

## Technical Questions

1. **Is interface-based BGP peering on a VRF master interface supposed to work for enslaved interfaces?**
   - Should the passive listener `neighbor vrf_evpnz1 interface peer-group TALOS_PEERS` be able to accept connections from VMs on `vnet101`?
   - Or should we explicitly listen on `vnet101` instead of the VRF master?

2. **Do we need specific kernel or FRR settings for VRF BGP peering?**
   - Are there VRF-specific BGP configuration requirements we're missing?
   - Should there be additional `net.ipv4.tcp_l3mdev_accept` or similar sysctls?

3. **Passive vs Active interface peering with VRF:**
   - The Proxmox side uses passive peering (`neighbor vrf_evpnz1 interface`)
   - The VM side uses active peering (`neighbor eth0 interface`)
   - Is this asymmetric setup valid for VRF scenarios?

4. **Firewall or packet capture insights:**
   - Should we expect to see BGP packets (TCP port 179) arriving at the VRF interface?
   - Would `tcpdump` on `vnet101` vs `vrf_evpnz1` show different results?

5. **Alternative configuration approach:**
   - Should we list specific interface neighbors instead of using the VRF master?
   - Example: `neighbor vnet101 interface peer-group TALOS_PEERS`
   - Or use traditional peering with link-local addresses?

## What We've Already Tried

- ✅ Verified ASN ranges match (4210000000-4210999999 on Proxmox, 4210101006 on VM)
- ✅ Confirmed MP-BGP with `capability extended-nexthop` is enabled on both sides
- ✅ Verified network connectivity (ping works both directions)
- ✅ Checked FRR versions (Proxmox: 10.5.0, VM: 10.2)
- ✅ Confirmed `ttl-security hops 1` is set on both sides
- ✅ Verified timers match (10/30)

## Expected Outcome

BGP sessions should establish and exchange routes:
- Proxmox should advertise default routes (0.0.0.0/0, ::/0) to VMs
- VMs should advertise their loopback addresses to Proxmox
- Both sides should show `Established` state with route counts

## Root Cause Analysis

After researching FRR documentation and GitHub issues, I believe the problem is:

**INCORRECT Configuration (current):**
```
neighbor vrf_evpnz1 interface peer-group TALOS_PEERS
```

This attempts to use the VRF master interface as a neighbor, but BGP traffic actually arrives on the **enslaved interfaces** (vnet101, vnet102, etc.). FRR examples show that interface-based peering requires specifying the **actual physical/virtual interface** where packets arrive, not the VRF master.

**PROPOSED Configuration:**
```
{% for vlan_id in TENANT_VLANS | sort %}
neighbor vnet{{ vlan_id }} interface peer-group TALOS_PEERS
{% endfor %}
```

This would create:
```
neighbor vnet101 interface peer-group TALOS_PEERS
neighbor vnet102 interface peer-group TALOS_PEERS
neighbor vnet103 interface peer-group TALOS_PEERS
```

## Request for Help

**Questions:**

1. **Is this the correct approach?** Should we explicitly list each vnet interface as a BGP neighbor instead of using the VRF master?

2. **Is there a dynamic alternative?** Can FRR accept BGP connections on all interfaces enslaved to a VRF without listing each one explicitly? (Similar to `bgp listen range` but for interfaces within a VRF)

3. **Kernel requirements:** Do we need specific kernel parameters beyond `net.ipv4.tcp_l3mdev_accept=1` for this to work?

4. **Alternative solution:** Should we use `bgp listen range 10.0.101.0/24` (and other subnets) instead of interface-based peering for VRF scenarios?

Any guidance on the correct FRR configuration pattern for passive BGP peering with multiple VXLAN interfaces enslaved to a VRF would be greatly appreciated.

---

## Research Sources

### FRR Documentation
- [BGP — FRR latest documentation](https://docs.frrouting.org/en/latest/bgp.html)
- [EVPN — FRR latest documentation](https://docs.frrouting.org/en/latest/evpn.html)
- [VRF — VyOS documentation](https://docs.vyos.io/en/latest/configuration/vrf/)

### Configuration Examples and Guides
- [VXLAN: BGP EVPN with FRR](https://vincent.bernat.ch/en/blog/2017-vxlan-bgp-evpn)
- [Overlay SDN with VxLAN, BGP-EVPN and FRR](https://icicimov.github.io/blog/virtualization/Overlay-SDN-with-VxLAN-BGP-EVPN-and-FRR/)
- [Configuring a VRF to work properly for FRR (GitHub Wiki)](https://github.com/FRRouting/frr/wiki/Configuring-a-VRF-to-work-properly-for-FRR)
- [Dell EMC VXLAN BGP EVPN Configuration Guide](https://www.dell.com/support/manuals/en-in/dell-emc-smartfabric-os10/vxlan-evpn-ug-10-5-1-pub/)

### GitHub Issues (FRRouting)
- [BGP dynamic listen under VRF · Issue #2906](https://github.com/FRRouting/frr/issues/2906) - Documents that dynamic BGP neighbors don't work under VRF, resolved with kernel parameters
- [Incorrect FRR configuration with VRF · Issue #16355](https://github.com/FRRouting/frr/issues/16355) - Shows examples of `neighbor <interface> interface peer-group` within VRF context
- [Per-interface BGP listen for IPv6 link-local peers · Issue #9465](https://github.com/FRRouting/frr/issues/9465)

### Key Findings from Research
- Interface-based BGP peering requires specifying the **actual interface** (e.g., `vnet101`) not the VRF master
- Kernel parameter `net.ipv4.tcp_l3mdev_accept=1` is required for BGP to listen on VRF interfaces
- `bgp listen range` has had historical issues with VRF contexts (may be fixed in recent versions)
- FRR examples show pattern: `neighbor <specific-interface> interface peer-group <name>` within `router bgp <ASN> vrf <vrf-name>` blocks
