# Research Prompt: Linux VRF + IPv6 EVPN GUA Routing Issue

## Title
Linux VRF + IPv6 EVPN: ULA Traffic Works, GUA Traffic Silently Dropped

## Problem Statement
I am troubleshooting a Proxmox VE 8.3 SDN EVPN deployment where IPv6 ULA traffic routes successfully, but IPv6 GUA traffic is silently dropped, despite identical routing, interfaces, and BGP propagation. This behavior appears illogical and suggests kernel-level or Proxmox-specific handling differences between ULA and GUA in a VRF context.

## Environment

- **Platform**: Proxmox VE 8.3
- **SDN Type**: EVPN zone (FRR controller)
- **VRF**: `vrf_evpnz1`
  - `exit_nodes_local_routing = true`
  - `snat = false` (no NAT; real source addresses required)
- **Kernel**: Proxmox default (Linux ≥6.x)
- **Routing Stack**: Linux VRF + FRR (l2vpn evpn, BGP)

## Addressing & Interfaces

VMs connected to `vnet101`. Each VM receives **both**:
- **ULA**: `fd00:101::/64`
- **GUA**: `2600:1700:ab1a:500e::/64`

Addresses are assigned via **SLAAC on the same interface**.
- Same L2, same L3, same VRF

## Routing

**Inside VRF (`vrf_evpnz1`):**
```
ipv6 route ::/0 fd00:10::ffff
```
- Default gateway reachable
- No policy routing differences between ULA/GUA
- No SNAT
- No firewall rules dropping traffic

**Upstream Router (RouterOS):**
- Receives both ULA and GUA prefixes via BGP
- Installs routes correctly
- Has return paths for both

## What Works

VMs using **ULA source addresses** (`fd00:101::x`) can:
- Reach internet IPv6 destinations
- Generate traffic that appears on `tcpdump` on `vnet101`

`ip -6 route get 2606:4700:4700::1111`:
- Correctly selects GUA when queried

VRF default route is present and correct

## What Fails

VMs using **GUA source addresses**:
- Cannot reach internet destinations
- `ping -6 -I 2600:...` produces **no packets**

`tcpdump` on `vnet101`:
- **No outbound packets** when GUA is the source
- Same command with ULA source works immediately

Packets appear to be **dropped before hitting the vnet interface**

## Critical Observation

This is **not a routing problem**:
- Same VRF
- Same interface
- Same default route
- Same upstream BGP behavior

This strongly suggests:
- Kernel-level IPv6 scope enforcement
- VRF-specific IPv6 validation
- Proxmox SDN EVPN behavior specific to GUA handling

## Additional Technical Details

**Verification commands run:**
```bash
# VMs correctly select GUA as source
ip -6 route get 2606:4700:4700::1111
# Output: ... from 2600:1700:ab1a:500e:be24:11ff:fe2f:c6a3 ...

# But ping produces NO packets
ping -6 -I 2600:1700:ab1a:500e:be24:11ff:fe2f:c6a3 2606:4700:4700::1111

# tcpdump on vnet101 shows NOTHING
tcpdump -i vnet101 -nn host 2606:4700:4700::1111
# (empty output)

# Same with ULA works immediately
ping -6 -I fd00:101::xxx 2606:4700:4700::1111
# tcpdump shows packets
```

**VRF routing table:**
```bash
ip -6 route show vrf vrf_evpnz1
# Shows:
# default via fd00:10::ffff dev vmbr0.10
# fd00:101::/64 dev vnet101 proto kernel
# 2600:1700:ab1a:500e::/64 dev vnet101 proto kernel
```

**Interface details:**
```bash
ip link show vnet101
# vnet101@if15: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
#     master vrf_evpnz1

# Both ULA and GUA gateway addresses exist on vnet101
ip -6 addr show dev vnet101
# inet6 fd00:101::fffe/128 scope global
# inet6 2600:1700:ab1a:500e::fffe/128 scope global
# inet6 fe80::..../64 scope link
```

## Research Questions (Focus Areas)

Please investigate Linux kernel, Proxmox SDN, and FRR internals for explanations of this asymmetry:

### 1. Linux VRF internals
- Does the kernel treat IPv6 GUA differently from ULA inside a VRF?
- Are there scope or source-validation checks that reject GUAs before egress?
- Does VRF enslaved interface scope checking differ for ULA vs GUA?

### 2. IPv6 source address validation
- Is there an IPv6 equivalent of `rp_filter` that applies differently to GUA?
- Are there hidden checks tied to:
  - `addr_gen_mode`
  - `accept_ra`
  - `forwarding`
  - `use_tempaddr`
  - `seg6_enabled`
  - VRF + SLAAC interaction?

### 3. Proxmox SDN EVPN
- Does Proxmox restrict GUA forwarding without SNAT in EVPN VRFs?
- Are GUAs implicitly assumed to require NAT or routed-only via the host?
- Is `exit_nodes_local_routing` ULA-biased?
- Does the SDN code have hardcoded scope checks?

### 4. FRR EVPN behavior
- Can FRR `l2vpn evpn` or VRF import/export logic filter or suppress GUA traffic?
- Are next-hop resolution or `xvrf` device constraints involved?
- Does `advertise-svi-ip` behave differently for ULA vs GUA?

### 5. xvrf / vrf device plumbing
- Does the VRF → vnet → bridge path apply scope filtering?
- Are packets dropped due to source scope mismatch with the egress interface?
- Is there a kernel check like "GUA sources must not use ULA gateways"?

### 6. IPv6 Neighbor Discovery / SLAAC
- Could there be ND/RA-related state preventing GUA forwarding?
- Does kernel track "learned via RA" differently from "static"?
- Are there IPv6 privacy extensions interfering?

## Desired Outcome

I am looking for:

1. **A technical explanation** of why ULA traffic is allowed while GUA traffic is dropped
2. **Confirmation** whether this is:
   - A Linux kernel behavior
   - A Proxmox SDN design decision
   - A misconfiguration requirement (sysctl, RA, VRF flag)
3. **A clear method** to enable GUA routing in a Proxmox EVPN VRF without SNAT

## Why This Matters

Using SNAT defeats the purpose of GUA addressing:
- Loses end-to-end addressability
- Breaks IPv6 architectural principles
- Makes VM addresses non-routable
- Prevents inbound connections to GUA addresses

The goal is **true dual-stack**: VMs use ULA for internal communication and GUA for internet access, both without NAT.

---

---

## BREAKTHROUGH FINDING

**Root Cause Identified**: VMs receive both ULA and GUA addresses via SLAAC, but Router Advertisements only advertise a **ULA gateway** (`fd00:101::ffff`) as the default route, not the GUA gateway (`2600:1700:ab1a:500e::ffff`).

**Evidence**:
```bash
# VM routing table shows GUA source but ULA gateway:
ip -6 route get 2606:4700:4700::1111
# Output: ... via fd00:101::ffff ... src 2600:1700:ab1a:500e:be24:11ff:fe2f:c6a3

# VM only has ULA default route:
ip -6 route show
# default via fd00:101::ffff dev eth0 proto static metric 1024
```

**The Problem**: Linux kernel rejects packets with **GUA source addresses trying to use ULA gateway** due to IPv6 source address validation. This is why:
- ULA → ULA gateway works (scope match)
- GUA → ULA gateway fails (scope mismatch) - **packets dropped before egress**

**The Fix**: Proxmox SDN must send Router Advertisements from **both** gateway addresses (ULA and GUA), so VMs learn:
- `default via fd00:101::ffff` (for ULA traffic)
- `default via 2600:1700:ab1a:500e::ffff` (for GUA traffic)

Or use a **single link-local gateway** that forwards both address scopes.

---

## Copy-Paste Version for ChatGPT/Claude

```
I am troubleshooting a Proxmox VE 8.3 SDN EVPN deployment where IPv6 ULA traffic routes successfully, but IPv6 GUA traffic is silently dropped, despite identical routing, interfaces, and BGP propagation.

Environment:
- Proxmox VE 8.3, EVPN zone with FRR controller
- VRF: vrf_evpnz1, exit_nodes_local_routing=true, snat=false
- VMs on vnet101 receive both ULA (fd00:101::/64) and GUA (2600:1700:ab1a:500e::/64) via SLAAC on the same interface
- VRF has default route: ipv6 route ::/0 fd00:10::ffff
- Upstream RouterOS receives and routes both ULA and GUA prefixes via BGP

What works:
- VMs using ULA source addresses can reach internet
- tcpdump shows packets leaving vnet101 with ULA source
- ip -6 route get correctly selects GUA as preferred source

What fails:
- VMs using GUA source addresses cannot reach internet
- ping -6 -I 2600:... produces ZERO packets (tcpdump shows nothing)
- Same ping with ULA source works immediately
- Packets appear dropped before reaching vnet interface

This is NOT a routing problem - same VRF, same interface, same default route, same BGP. This suggests kernel-level IPv6 scope enforcement or VRF-specific validation.

Please investigate:
1. Does Linux VRF treat IPv6 GUA differently from ULA?
2. Are there scope/source-validation checks rejecting GUAs before egress?
3. Is there an IPv6 rp_filter equivalent applying differently to GUA?
4. Does Proxmox SDN restrict GUA forwarding without SNAT in EVPN VRFs?
5. Can FRR l2vpn evpn filter GUA traffic?
6. Are packets dropped due to source scope mismatch in VRF → vnet → bridge path?

Goal: Enable GUA routing in Proxmox EVPN VRF without SNAT (true dual-stack: ULA for internal, GUA for internet).
```
