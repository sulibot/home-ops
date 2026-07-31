# ChatGPT: xvrf Cross-Connect Routing Issue (After Fixing Anti-Spoof)

## Current Status - UPDATED

✅ **SOLVED**: Proxmox SDN anti-spoof filter blocking xvrf traffic
- Added `vnet999` with subnet `fd00:255:254::/127` to Terraform SDN config
- Applied SDN changes: `terraform apply` + `pvesh set /cluster/sdn`
- **Ping now works** across xvrf veth pair (VRF ↔ global)

❌ **NEW PROBLEM**: Routing from VRF through xvrf to RouterOS fails
- VRF can ping xvrf global side (`fd00:255:254::1`) ✅
- But VRF cannot reach RouterOS (`fd00:10::ffff`) through xvrf ❌
- Error: "Beyond scope of source address"

## What Works Now ✅

```bash
# xvrf veth pair connectivity is working
ip vrf exec vrf_evpnz1 ping -6 fd00:255:254::1
# 64 bytes from fd00:255:254::1: icmp_seq=1 ttl=64 time=0.034 ms
# SUCCESS!
```

## What Still Fails ❌

```bash
# Cannot reach RouterOS from VRF
ip vrf exec vrf_evpnz1 ping -6 fd00:10::ffff
# From fe80::f091:5eff:fe3a:32ae%xvrfp_evpnz1 icmp_seq=1
# Destination unreachable: Beyond scope of source address

# Traceroute shows packets stop at xvrf
ip vrf exec vrf_evpnz1 traceroute -6 fd00:10::ffff
# 1  fe80::f091:5eff:fe3a:32ae%xvrfp_evpnz1 (...)  0.046 ms
# 2  fe80::f091:5eff:fe3a:32ae%xvrfp_evpnz1 (...)  0.007 ms !H

# BGP session still shows "Connect"
vtysh -c 'show bgp vrf vrf_evpnz1 summary'
# fd00:10::ffff   4 4200000000   0   0   0   0   0   never   Connect   0
```

## Current Configuration

### xvrf Addresses (Working)
```bash
# Global side
ip -6 addr show dev xvrf_evpnz1
# inet6 fd00:255:254::1/127 scope global

# VRF side
ip vrf exec vrf_evpnz1 ip -6 addr show dev xvrfp_evpnz1
# inet6 fd00:255:254::2/127 scope global
# master vrf_evpnz1
```

### FRR Static Routes in VRF
```
vrf vrf_evpnz1
  ip route 0.0.0.0/0 10.0.10.254
  ipv6 route ::/0 fd00:10::ffff
  ipv6 route fd00:10::/64 fd00:255:254::1  # Route fd00:10::/64 via xvrf
exit-vrf
```

### FRR BGP in VRF
```
router bgp 4200001000 vrf vrf_evpnz1
  neighbor fd00:10::ffff remote-as 4200000000
  neighbor fd00:10::ffff description "MikroTik edge via xvrf"
  neighbor fd00:10::ffff update-source fd00:255:254::2
  neighbor fd00:10::ffff ebgp-multihop 2

  address-family ipv6 unicast
    neighbor fd00:10::ffff activate
    neighbor fd00:10::ffff next-hop-self
    redistribute connected
```

### Routing Tables
```bash
# VRF routing table
ip -6 route show vrf vrf_evpnz1 | grep fd00:10
# fd00:10::/64 dev vmbr0.10 proto kernel metric 256

# Global routing table
ip -6 route get fd00:10::ffff
# fd00:10::ffff from :: dev vmbr0.10 proto kernel src fd00:10::1 metric 256

# vmbr0.10 is NOT in VRF
ip link show vmbr0.10
# 41: vmbr0.10@vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
# (no "master vrf_evpnz1")
```

## Problem Analysis

**Desired Traffic Flow:**
1. BGP packet from VRF: source=`fd00:255:254::2`, dest=`fd00:10::ffff`
2. VRF routes to xvrf: via `fd00:255:254::1` (static route `ipv6 route fd00:10::/64 fd00:255:254::1`)
3. Packet reaches xvrf global side (`xvrf_evpnz1`)
4. Global table should forward to vmbr0.10 → RouterOS

**What's Actually Happening:**
- Packet reaches xvrf global side
- But gets rejected with "Beyond scope of source address"
- xvrf_evpnz1 doesn't know how to forward packets with source `fd00:255:254::2` to `fd00:10::ffff`

**Key Issue**: The xvrf interface has address `fd00:255:254::1/127`, which is NOT in the `fd00:10::/64` subnet. When trying to forward to `fd00:10::ffff` via vmbr0.10, the kernel can't select a valid source address or the forwarding fails due to scope/subnet mismatch.

## Questions for ChatGPT

### 1. How should forwarding work from xvrf (global) to vmbr0.10?

When a packet arrives at `xvrf_evpnz1` (global side) with:
- Source: `fd00:255:254::2` (from VRF)
- Destination: `fd00:10::ffff` (RouterOS on vmbr0.10)

How should Linux forward this packet? Do I need:
- A specific forwarding rule?
- Policy-based routing?
- NAT/masquerade (defeats the purpose)?
- A different addressing scheme?

### 2. Should xvrf_evpnz1 have an address in fd00:10::/64?

Currently:
- xvrf_evpnz1: `fd00:255:254::1/127`
- vmbr0.10: `fd00:10::1/64`
- RouterOS: `fd00:10::ffff`

Should I instead configure:
- xvrf_evpnz1: `fd00:10::X/64` (some address in the management subnet)?
- Would this allow proper forwarding between xvrf and vmbr0.10?

### 3. Is the BGP update-source correct?

BGP config uses:
```
neighbor fd00:10::ffff update-source fd00:255:254::2
```

This means BGP packets will have source `fd00:255:254::2`. But RouterOS is in `fd00:10::/64` and won't have a route back to `fd00:255:254::/127` unless we advertise it via BGP (which hasn't established yet - chicken/egg problem).

Should I:
- Remove `update-source` and let BGP choose automatically?
- Add a static route on RouterOS for `fd00:255:254::/127`?
- Use a different source address?

### 4. Do I need proxy_ndp or other kernel settings?

Are there kernel parameters needed for forwarding between xvrf and vmbr0.10?
```bash
net.ipv6.conf.xvrf_evpnz1.proxy_ndp?
net.ipv6.conf.xvrf_evpnz1.accept_ra?
net.ipv6.conf.all.forwarding=1  # Already enabled
```

### 5. Alternative: Should I use link-local addresses for BGP?

Instead of GUA addresses, should the xvrf pair and BGP session use link-local addresses?
```
xvrf_evpnz1: fe80::1/64
xvrfp_evpnz1: fe80::2/64
neighbor fe80::X%xvrfp_evpnz1 remote-as ...
```

Would this avoid the routing/scope issues?

## Environment

- **Proxmox VE**: 9.1 (Debian 12, Linux 6.8 kernel)
- **SDN**: EVPN zone with FRR controller, VRF `vrf_evpnz1`
- **xvrf veth pair**: Created automatically by Proxmox SDN
- **Subnet now whitelisted**: `vnet999` with `fd00:255:254::/127` in SDN IPAM
- **Goal**: BGP from VRF to RouterOS (`fd00:10::ffff`) in global table

## What I've Tried

1. ✅ Added `/127` to SDN IPAM - **SOLVED** anti-spoof filter issue
2. ✅ Configured static route in VRF: `ipv6 route fd00:10::/64 fd00:255:254::1`
3. ✅ xvrf veth pair ping works in both directions
4. ❌ VRF still can't reach RouterOS through xvrf
5. ❌ BGP session won't establish

## What I Need

**Specific configuration** to enable proper IPv6 forwarding from VRF (`fd00:255:254::2`) through xvrf to vmbr0.10 (`fd00:10::/64`) so BGP can establish to RouterOS.

The xvrf link works, but I'm missing the forwarding configuration or addressing to make traffic actually flow through to the management network.

---

**Bottom line**: Anti-spoof filter is fixed, xvrf pair works, but packets can't forward from xvrf (global) to vmbr0.10 due to scope/addressing issues. Need help with the routing/forwarding configuration.
