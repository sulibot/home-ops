# ChatGPT Research Prompt: FRR VRF Import Next-Hop Issue

## Problem Statement

I'm using FRR (Free Range Routing) to advertise routes from a VRF to an external BGP peer (RouterOS). The `import vrf` command successfully imports routes from the VRF into the global BGP table, but the imported routes have next-hop `::` (unspecified/unreachable) instead of a reachable address.

I've tried using a route-map with `set ipv6 next-hop global` to rewrite the next-hop, but FRR appears to ignore this for VRF-imported routes.

## Current Configuration

**FRR Configuration** (ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2):

Lines 60-62: Route-map to set next-hop
```
route-map VRF_TO_EDGE permit 10
  set ipv6 next-hop global fd00:10::{{ PVE_ID }}
exit
```

Lines 130-138: BGP IPv6 address-family configuration
```
address-family ipv6 unicast
  redistribute connected route-map EXPORT_V6_CONNECTED
  ! Import VRF routes to advertise VNet subnets to RouterOS
  ! Note: table-map doesn't work with import vrf, so we use route-map on neighbor out
  import vrf vrf_evpnz1
  neighbor {{ EDGE_V6_PEER }} activate
  neighbor {{ EDGE_V6_PEER }} route-map VRF_TO_EDGE out
  ! next-hop-self doesn't work for VRF-imported routes, route-map handles it
  neighbor {{ EDGE_V6_PEER }} next-hop-self force
```

Lines 171-235: VRF BGP configuration (where routes originate)
```
router bgp {{ PVE_ASN }} vrf vrf_evpnz1
  bgp router-id 10.0.10.{{ PVE_ID }}
  no bgp default ipv4-unicast

  address-family ipv6 unicast
    redistribute connected
    # ... (Talos peering config)
  exit-address-family

  ! Advertise VRF routes into EVPN (Type-5 routes)
  address-family l2vpn evpn
    advertise ipv4 unicast
    advertise ipv6 unicast
  exit-address-family
exit
```

## Observed Behavior

When checking the advertised routes:
```bash
vtysh -c 'show bgp ipv6 unicast neighbors fd00:10::ffff advertised-routes'
```

Output shows:
```
 *>  2600:1700:ab1a:500e::/64
                    ::@21<                   0         32768 ?
```

The `::@21<` indicates next-hop `::` from VRF table 21.

The route-map IS being invoked (32 times according to `show route-map VRF_TO_EDGE`), but the next-hop rewriting doesn't seem to apply to VRF-imported routes.

## What Works

- Route-map invocation count increases ✅
- Routes are successfully imported from VRF ✅
- Routes are advertised to BGP neighbor ✅

## What Doesn't Work

- Next-hop is still `::` instead of `fd00:10::1` ❌
- `next-hop-self force` doesn't affect VRF-imported routes ❌
- Route-map `set ipv6 next-hop global` appears ignored for these routes ❌

## Questions

1. **Is this the correct approach?** Should `import vrf` routes be handled differently than regular BGP routes when it comes to next-hop rewriting?

2. **Is there a fundamental architectural issue?** Am I trying to use `import vrf` in a way it wasn't designed for?

3. **Alternative approaches?** Should I be using:
   - L2VPN EVPN Type-5 routes instead of `import vrf`?
   - Route redistribution instead of VRF import?
   - A different next-hop rewriting mechanism?

4. **FRR limitations?** Is there a known limitation in FRR where route-maps don't apply to VRF-imported routes' next-hops?

5. **Configuration order?** Does the order of `import vrf vrf_evpnz1` vs `neighbor X route-map Y out` matter?

## Environment

- FRR version: Running on Proxmox VE 8.3 (default FRR package)
- Use case: Advertising Proxmox SDN EVPN VNet subnets to upstream RouterOS router
- VRF: vrf_evpnz1 contains VM network subnets
- Goal: Advertise VRF subnets to RouterOS with reachable next-hop (fd00:10::1)

## Expected Behavior

Routes imported from VRF should be advertised with next-hop set to `fd00:10::1` (the PVE host's management IP), allowing RouterOS to route return traffic correctly.

## Request

Please analyze the FRR configuration and help identify:
1. Why the route-map isn't rewriting next-hop for VRF-imported routes
2. Whether this is the correct architectural approach
3. The proper FRR configuration pattern for this use case
4. Any fundamental misunderstanding of how FRR's `import vrf` or route-maps work

Thank you!
