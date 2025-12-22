# GUA Routing Issue - Root Cause Analysis

## Summary

VMs in Proxmox SDN EVPN VRF cannot reach the internet, period. Neither ULA nor GUA traffic works from VMs.

## ACTUAL Root Cause (Updated)

**RouterOS does not route ULA addresses (fd00::/8) to the internet.**

VMs are using ULA gateway (`fd00:101::ffff`) as their default route, which means all internet-bound traffic has **ULA source addresses**. RouterOS requires **GUA source addresses** for internet routing.

## Secondary Issue

Even if VMs used GUA source addresses, RouterOS cannot route return traffic to `2600:1700:ab1a:500e::/64` (VNet GUA subnet) because FRR's BGP advertisement has unreachable next-hop

### Evidence

1. **Packets successfully egress from VRF to vmbr0.10**:
   ```bash
   # tcpdump on vmbr0.10 shows GUA packets leaving:
   IP6 2600:1700:ab1a:500e::ffff > 2606:4700:4700::1111: ICMP6, echo request
   ```

2. **FRR is advertising the GUA subnet to RouterOS**:
   ```bash
   vtysh -c 'show bgp ipv6 unicast 2600:1700:ab1a:500e::/64'
   # Advertised to peers: fd00:10::ffff
   ```

3. **PVE host's SLAAC GUA works (different /64)**:
   ```bash
   # This works:
   ping -6 -I 2600:1700:ab1a:500c:aab8:e0ff:fe04:4aec 2606:4700:4700::1111
   # SUCCESS

   # This fails:
   ping -6 -I 2600:1700:ab1a:500e::ffff 2606:4700:4700::1111
   # 100% packet loss (no return traffic)
   ```

## Network Architecture

### GUA Prefix Allocation

AT&T DHCPv6-PD delegates: `2600:1700:ab1a:5000::/56`

**Current allocation**:
- `2600:1700:ab1a:500c::/64` - VLAN 10 management (PVE hosts) - **WORKS**
- `2600:1700:ab1a:500e::/64` - VNet101 (Talos cluster-101) - **FAILS**

### Traffic Flow

```
VM (2600:1700:ab1a:500e::xxx)
  ↓
vnet101 (VRF: vrf_evpnz1)
  ↓
xvrfp_evpnz1 (VRF exit)
  ↓
vmbr0.10 (management VLAN)
  ↓
RouterOS (fd00:10::ffff / fe80::ff:fe00:1)
  ↓
Internet

← Return traffic FAILS here
```

## What Works vs. What Fails

### ✅ Works
- VM ULA → Internet (fd00:101::xxx → 2606:4700:4700::1111)
- PVE SLAAC GUA → Internet (2600:1700:ab1a:500**c**::xxx → 2606:4700:4700::1111)
- VRF → vmbr0.10 forwarding (packets visible on tcpdump)
- FRR BGP advertisement to RouterOS

### ❌ Fails
- VM GUA → Internet (2600:1700:ab1a:500**e**::xxx → 2606:4700:4700::1111)
- VRF GUA gateway → Internet (2600:1700:ab1a:500e::ffff → any)
- Return traffic to 2600:1700:ab1a:500e::/64

## Hypothesis

RouterOS is either:
1. Not installing the BGP route for `2600:1700:ab1a:500e::/64`
2. Installing the route but with wrong next-hop (can't reach it)
3. Installing the route but firewall/filter is blocking return traffic

## Next Steps

### Verify RouterOS BGP State

```bash
# Check if RouterOS received the route:
/ipv6 route print where dst-address="2600:1700:ab1a:500e::/64"

# Check BGP routes:
/routing bgp advertisements print where prefix="2600:1700:ab1a:500e::/64"

# Check active routes:
/ipv6 route print where active
```

### Verify Next-Hop Reachability

```bash
# From RouterOS, can it ping PVE?
/ping address=fd00:10::1 count=2

# Can RouterOS reach the VRF gateway?
/ping address=2600:1700:ab1a:500e::ffff count=2
```

### Check Firewall Rules

```bash
# RouterOS firewall might be blocking:
/ipv6 firewall filter print where chain=forward
```

## Temporary Workaround

Add static route on RouterOS:
```bash
/ipv6 route add dst-address=2600:1700:ab1a:500e::/64 gateway=fd00:10::1
```

## Permanent Fix

1. Verify FRR is exporting VRF routes correctly (✅ confirmed working)
2. Ensure RouterOS BGP session is importing the routes
3. Verify next-hop is reachable (likely issue: next-hop might be `::`  which is unreachable)
4. Fix FRR to advertise routes with correct next-hop (fd00:10::1 for PVE01)

### Check FRR Next-Hop

```bash
# On PVE, check what next-hop is being advertised:
vtysh -c 'show bgp ipv6 unicast neighbors fd00:10::ffff advertised-routes'
# Look for next-hop field for 2600:1700:ab1a:500e::/64
```

The issue is likely **FRR advertising VRF routes with next-hop `::`** instead of the PVE host's management IP (fd00:10::1).

## Configuration Review Required

### FRR BGP Configuration

Check if these are configured:
- `neighbor fd00:10::ffff next-hop-self` ✅ (present on line 136)
- VRF route export is working ✅ (confirmed via show bgp)
- Routes are being imported from VRF ✅ (`import vrf vrf_evpnz1` on line 133)

The `announce-nh-self` in the BGP output suggests FRR is trying to set itself as next-hop, but RouterOS might not be accepting it properly.

## Related Files

- [frr-pve.conf.j2](../ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2:133-136) - BGP VRF import config
- [proxmox_sdn/main.tf](../terraform/infra/modules/proxmox_sdn/main.tf:47-56) - GUA subnet definition
