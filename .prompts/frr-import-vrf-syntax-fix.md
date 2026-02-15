# FRR 10.5.1 `import vrf` Syntax Issue — Verify Fix

## Goal
Fix the `import vrf` syntax in our FRR Jinja2 template so that VRF route leaking works correctly on FRR 10.5.1 (Debian Trixie / Proxmox 9). The template is the single source of truth for FRR config on 3 Proxmox nodes.

## The Problem
VRF route leaking is **silently broken**. FRR loads the config without errors but ignores the `import vrf` lines entirely. Routes in `vrf_evpnz1` (tenant subnets like `10.101.0.0/24`) never appear in the global routing table, so they're never advertised via eBGP to the upstream router (RouterOS). Result: tenant VMs are reachable from PVE nodes but unreachable from the rest of the network.

## Evidence

### Template syntax (BROKEN — 4 affected lines):
```
# In router bgp 4200001000 / address-family ipv4 unicast:
  import vrf vrf_evpnz1 route-map RM_VRF_TO_GLOBAL_V4

# In router bgp 4200001000 / address-family ipv6 unicast:
  import vrf vrf_evpnz1 route-map RM_VRF_TO_GLOBAL_V6

# In router bgp 4200001000 vrf vrf_evpnz1 / address-family ipv4 unicast:
  import vrf default route-map RM_GLOBAL_TO_VRF_V4

# In router bgp 4200001000 vrf vrf_evpnz1 / address-family ipv6 unicast:
  import vrf default route-map RM_GLOBAL_TO_VRF_V6
```

### What happens after FRR loads this config:
```
# show running-config | grep import
 no bgp network import-check
```
**Zero `import vrf` lines in running config.** FRR silently discards the combined `import vrf X route-map Y` syntax.

### Manual fix that WORKS (tested live on all 3 nodes):
```
# Two separate commands instead of one combined:
vtysh -c 'conf t' \
  -c 'router bgp 4200001000' \
  -c 'address-family ipv4 unicast' \
  -c 'import vrf vrf_evpnz1' \
  -c 'import vrf route-map RM_VRF_TO_GLOBAL_V4' \
  -c 'end'
```

### After applying the fix:
```
# show running-config | grep import
 no bgp network import-check
  import vrf route-map RM_VRF_TO_GLOBAL_V4
  import vrf vrf_evpnz1
  import vrf route-map RM_VRF_TO_GLOBAL_V6
  import vrf vrf_evpnz1
  import vrf route-map RM_GLOBAL_TO_VRF_V4
  import vrf default
  import vrf route-map RM_GLOBAL_TO_VRF_V6
  import vrf default

# show ip route 10.101.0.0/24
Routing entry for 10.101.0.0/24
  Known via "bgp", distance 20, metric 0, best
  * directly connected, vrf_evpnz1(vrf vrf_evpnz1), weight 1
```

## Template File
`ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

### Current broken lines (lines 349, 356, 385, 393):
```jinja2
{# Global BGP — address-family ipv4 #}
  import vrf {{ VRF_NAME }} route-map RM_VRF_TO_GLOBAL_V4

{# Global BGP — address-family ipv6 #}
  import vrf {{ VRF_NAME }} route-map RM_VRF_TO_GLOBAL_V6

{# VRF BGP — address-family ipv4 #}
  import vrf default route-map RM_GLOBAL_TO_VRF_V4

{# VRF BGP — address-family ipv6 #}
  import vrf default route-map RM_GLOBAL_TO_VRF_V6
```

## Proposed Fix
Split each combined `import vrf X route-map Y` into two separate lines:

```jinja2
{# Global BGP — address-family ipv4 #}
  import vrf {{ VRF_NAME }}
  import vrf route-map RM_VRF_TO_GLOBAL_V4

{# Global BGP — address-family ipv6 #}
  import vrf {{ VRF_NAME }}
  import vrf route-map RM_VRF_TO_GLOBAL_V6

{# VRF BGP — address-family ipv4 #}
  import vrf default
  import vrf route-map RM_GLOBAL_TO_VRF_V4

{# VRF BGP — address-family ipv6 #}
  import vrf default
  import vrf route-map RM_GLOBAL_TO_VRF_V6
```

## Your Task
1. **Verify** that the proposed fix matches FRR 10.5.1's actual syntax for VRF route leaking with route-map filtering
2. **Confirm** that `import vrf <name>` and `import vrf route-map <name>` are indeed separate commands in FRR 10.x (not a single combined command)
3. **Check** if there's any ordering requirement (does `import vrf route-map` need to come before or after `import vrf <name>`?)
4. **Review** the full template context below and confirm the fix won't break anything else
5. **Flag** any other issues you notice in the template

## Environment
- FRR version: 10.5.1
- OS: Debian 13 (Trixie) / Proxmox VE 9
- 3 nodes: pve01, pve02, pve03
- VRF: `vrf_evpnz1` (EVPN zone with VXLAN overlay)
- ASN: 4200001000 (PVE), 4200000000 (upstream RouterOS)
