# IPv6 Prefix Allocation

This document describes all IPv6 prefixes used in the home-ops infrastructure.

## Architecture Overview

The infrastructure uses **dual-stack IPv6** addressing:
- **ULA (Unique Local Address)** - fd00::/8 - Stable internal addressing
- **GUA (Global Unicast Address)** - 2600:1700:ab1a::/48 - Internet-routable addresses from AT&T

VMs and services receive BOTH address types via SLAAC, providing:
- Stable internal connectivity (ULA persists even if ISP changes prefix)
- Direct internet routing (GUA provides public accessibility)

## Prefix Allocation

### Management/Infrastructure Network (VLAN 10)

| Type | Prefix | Gateway | Purpose |
|------|--------|---------|---------|
| ULA  | fd00:10::/64 | fd00:10::ffff | Internal management |
| GUA  | 2600:1700:ab1a:500c::/64 | 2600:1700:ab1a:500c::ffff | Internet access for PVE hosts |

**Static Assignments:**
- `fd00:10::1` - pve01 (ULA only, GUA via SLAAC)
- `fd00:10::2` - pve02 (ULA only, GUA via SLAAC)
- `fd00:10::3` - pve03 (ULA only, GUA via SLAAC)
- `fd00:10::ffff` / `2600:1700:ab1a:500c::ffff` - RouterOS gateway

**Router Advertisements:**
- RouterOS sends RAs with both ULA (fd00:10::/64) and GUA (2600:1700:ab1a:500c::/64) prefixes
- PVE hosts receive GUA addresses via SLAAC (e.g., 2600:1700:ab1a:500c::1 on pve01)

### VNet 100 - General Workloads

| Type | Prefix | Gateway | Purpose |
|------|--------|---------|---------|
| ULA  | fd00:100::/64 | fd00:100::ffff | Internal workload communication |
| GUA  | 2600:1700:ab1a:5009::/64 | 2600:1700:ab1a:5009::ffff | Internet-routable workload addresses |

**VXLAN ID:** 10100

### VNet 101 - Talos Cluster 101

| Type | Prefix | Gateway | Purpose |
|------|--------|---------|---------|
| ULA  | fd00:101::/64 | fd00:101::ffff | Internal cluster communication |
| GUA  | 2600:1700:ab1a:500e::/64 | 2600:1700:ab1a:500e::ffff | Internet-routable cluster services |

**VXLAN ID:** 10101

**Static Assignments (ens18 interface):**
- `fd00:101::11` - solcp01 (ULA only, GUA via SLAAC)
- `fd00:101::12` - solcp02 (ULA only, GUA via SLAAC)
- `fd00:101::13` - solcp03 (ULA only, GUA via SLAAC)
- `fd00:101::21` - solwk01 (ULA only, GUA via SLAAC)
- `fd00:101::22` - solwk02 (ULA only, GUA via SLAAC)
- `fd00:101::23` - solwk03 (ULA only, GUA via SLAAC)

**Router Advertisements:**
- Proxmox SDN sends RAs with both ULA (fd00:101::/64) and GUA (2600:1700:ab1a:500e::/64) prefixes
- Talos nodes receive GUA addresses via SLAAC on ens18

### VNet 102 - Talos Cluster 102

| Type | Prefix | Gateway | Purpose |
|------|--------|---------|---------|
| ULA  | fd00:102::/64 | fd00:102::ffff | Internal cluster communication |
| GUA  | 2600:1700:ab1a:500b::/64 | 2600:1700:ab1a:500b::ffff | Internet-routable cluster services |

**VXLAN ID:** 10102

### VNet 103 - Talos Cluster 103

| Type | Prefix | Gateway | Purpose |
|------|--------|---------|---------|
| ULA  | fd00:103::/64 | fd00:103::ffff | Internal cluster communication |
| GUA  | 2600:1700:ab1a:5008::/64 | 2600:1700:ab1a:5008::ffff | Internet-routable cluster services |

**VXLAN ID:** 10103

### Loopback/Infrastructure Prefixes

| Prefix | Purpose |
|--------|---------|
| fd00:255::/64 | PVE host loopbacks (BGP router IDs) |
| fd00:255:101::/48 | Talos node loopbacks (cluster 101) |
| fc00:20::/64 | Ceph public network |
| fc00:21::/64 | Ceph cluster network |

**PVE Loopbacks:**
- `fd00:255::1` / `10.255.0.1` - pve01 BGP router ID
- `fd00:255::2` / `10.255.0.2` - pve02 BGP router ID
- `fd00:255::3` / `10.255.0.3` - pve03 BGP router ID

**Talos Loopbacks (example for cluster 101):**
- `fd00:255:101::11` / `10.255.101.11` - solcp01
- `fd00:255:101::12` / `10.255.101.12` - solcp02
- `fd00:255:101::13` / `10.255.101.13` - solcp03
- `fd00:255:101::21` / `10.255.101.21` - solwk01
- `fd00:255:101::22` / `10.255.101.22` - solwk02
- `fd00:255:101::23` / `10.255.101.23` - solwk03

## GUA Prefix Delegation

### Source
AT&T Fiber delegates /64 prefixes via DHCPv6-PD to RouterOS.

### RouterOS Configuration
- **Requests** DHCPv6-PD from AT&T (keeps delegation active)
- **Does NOT assign** GUA to physical interfaces (prevents routing conflicts)
- **Advertises** GUA prefixes to Proxmox via BGP
- **Accepts** more-specific /128 routes from Proxmox via BGP

### Proxmox SDN Configuration
- **Assigns** both ULA and GUA to VNet interfaces
- **Sends** Router Advertisements for both prefixes
- **Advertises** GUA subnets back to RouterOS via BGP
- VMs receive addresses via SLAAC from both prefixes

## Routing Protocol

### BGP AS Numbers
- **RouterOS:** AS 65000 (edge router)
- **Proxmox FRR (underlay):** AS 4200001000
- **Talos Cluster 101 nodes:** AS 4210101011-4210101023
- **Cilium (overlay):** AS 4220101011-4220101023

### Route Advertisement
1. **RouterOS → Proxmox:** Default route + GUA prefixes
2. **Proxmox → RouterOS:** VNet GUA subnets + node loopbacks
3. **Talos → Proxmox:** Node loopbacks + pod CIDRs
4. **Cilium:** Internal overlay routing

## Address Selection

When a VM has both ULA and GUA addresses:
- **Internal traffic** (within home-ops): Uses ULA (shorter path, stays local)
- **Internet traffic**: Uses GUA (source address selection prefers public)
- **Inbound from internet**: Uses GUA (ULA not routable on internet)

## Benefits of Dual-Stack Approach

1. **Resilience**: Internal services continue working if ISP changes GUA prefix
2. **Simplicity**: No NAT - direct routing for both internal and internet traffic
3. **Future-proof**: Easy to expose services to internet (just allow inbound on GUA)
4. **Best practice**: Follows RFC 4193 and RFC 6724 address selection

## Maintenance

### When AT&T Changes Delegated Prefix

1. Update [terraform/infra/live/common/ipv6-prefixes.hcl](../terraform/infra/live/common/ipv6-prefixes.hcl)
2. Apply Terraform: `cd terraform/infra/live/common/0-sdn-setup && terragrunt apply`
3. Proxmox SDN will update Router Advertisements
4. VMs will get new GUA addresses via SLAAC (ULA unchanged)
5. Old GUA addresses deprecate after their lifetime expires

### Verification Commands

```bash
# Check PVE node addressing
ssh root@pve01.sulibot.com "ip -6 addr show dev vmbr0.10"

# Check VNet gateway addressing
ssh root@pve01.sulibot.com "ip -6 addr show dev vnet101"

# Check VM addressing
ssh root@pve01.sulibot.com "qm guest exec 100 -- ip -6 addr"

# Check BGP routes from RouterOS
ssh admin@fd00:10::ffff "ipv6 route print where bgp"

# Check BGP routes on Proxmox
ssh root@pve01.sulibot.com "vtysh -c 'show bgp ipv6 unicast'"
```

## References

- [RFC 4193](https://datatracker.ietf.org/doc/html/rfc4193) - Unique Local IPv6 Unicast Addresses
- [RFC 6724](https://datatracker.ietf.org/doc/html/rfc6724) - Default Address Selection for IPv6
- [RFC 8415](https://datatracker.ietf.org/doc/html/rfc8415) - DHCPv6-PD
