# RouterOS BGP Configuration for Cluster-101

This document describes the RouterOS BGP configuration required for Kubernetes cluster-101 after implementing the simplified Cilium BGP architecture.

## Architecture Overview

**Simplified Design** (Option 2):
- Both FRR and Cilium BGP use the **same egress loopback** (`fd00:255:101::X`)
- No mesh loopback (`fc00:255:101::X`) needed
- No source-based routing required
- Single BGP connection on ROS accepts both FRR and Cilium sessions
- Clean semantic separation: `fc00:` = internal only, `fd00:` = routable

## BGP Connection Configuration

A single BGP connection is configured on ROS to accept connections from both FRR and Cilium BGP instances running on the K8s nodes. Both use the same source loopback subnet (fd00:255:101::/64) for simplified configuration.

### Connection: K8s BGP (FRR VIP + Cilium LoadBalancer IPs)

This connection accepts BGP sessions from both:
- **FRR**: Advertises the Kubernetes VIP (fd00:255:101::ac/128)
- **Cilium BGP**: Advertises LoadBalancer service IPs (fd00:101:1b::/112 IPv6 and 10.101.27.0/24 IPv4)

```
/routing/bgp/connection/add \
  name=ebgp6-k8s-cluster-101 \
  as=65000 \
  listen=yes \
  remote.address=fd00:255:101::/64 \
  local.address=fd00:101::fffe
```

## Summary
- Single BGP connection listens on `fd00:101::fffe` (ROS vlan101 interface)
- Accepts from `fd00:255:101::/64` (egress loopback subnet used by both FRR and Cilium)
- FRR and Cilium create separate TCP sessions to the same listener (different source ports)
- Simplified architecture: **one loopback subnet instead of two**
- Supports dual-stack: IPv6 (primary) and IPv4 (for Plex, Home Assistant)

## Static Routes Required

The following static routes must be configured on ROS to make the egress loopback IPs reachable.
These routes direct traffic to the loopback IPs via the nodes' eth1 interface IPs.

### Egress Loopback Routes (fd00:255:101::/64)

```
/ipv6/route/add dst-address=fd00:255:101::11/128 gateway=fd00:101::11 comment="solcp011 egress loopback"
/ipv6/route/add dst-address=fd00:255:101::12/128 gateway=fd00:101::12 comment="solcp012 egress loopback"
/ipv6/route/add dst-address=fd00:255:101::13/128 gateway=fd00:101::13 comment="solcp013 egress loopback"
/ipv6/route/add dst-address=fd00:255:101::21/128 gateway=fd00:101::21 comment="solwk021 egress loopback"
/ipv6/route/add dst-address=fd00:255:101::22/128 gateway=fd00:101::22 comment="solwk022 egress loopback"
/ipv6/route/add dst-address=fd00:255:101::23/128 gateway=fd00:101::23 comment="solwk023 egress loopback"
```

## Verification

After applying the configuration, verify with:

```
# Check BGP connection
/routing/bgp/connection/print detail where name=ebgp6-k8s-cluster-101

# Check BGP sessions (should see 6 established sessions)
/routing/bgp/session/print where connection=ebgp6-k8s-cluster-101

# Check static routes
/ipv6/route/print where dst-address~"255:101"

# Monitor learned routes from K8s
/routing/route/print where bgp=yes

# Monitor BGP neighbor establishment
/routing/bgp/session/monitor
```

Expected BGP sessions:
- 6 total sessions (one per K8s node)
- All from `fd00:255:101::11-13, 21-23`
- Routes learned:
  - `fd00:255:101::ac/128` (K8s VIP, advertised by healthy control plane node)
  - `fd00:101:1b::/112` (LoadBalancer IPv6 pool, advertised by Cilium)
  - `10.101.27.0/24` (LoadBalancer IPv4 pool, advertised by Cilium)

## Configuration Persistence

All commands above are automatically persisted in ROS configuration. To backup:

```
/export file=bgp-cluster-101-simplified
```

## Migration Notes

If migrating from the previous dual-loopback architecture:

1. **Remove old BGP connection** (if exists):
   ```
   /routing/bgp/connection/remove ebgp6-cilium-101
   ```

2. **Remove old static routes** (if exist):
   ```
   /ipv6/route/remove [find dst-address~"fc00:255:101"]
   ```

3. **Rename existing connection** (if needed):
   ```
   /routing/bgp/connection/set ebgp6-in-v101 name=ebgp6-k8s-cluster-101
   /routing/bgp/connection/set ebgp6-k8s-cluster-101 remote.address=fd00:255:101::/64
   ```

## Benefits of Simplified Architecture

- ✅ Fewer BGP connections (1 instead of 2)
- ✅ Fewer static routes (6 instead of 12)
- ✅ No source-based routing needed on K8s nodes
- ✅ Clean semantic separation: fc00 = internal, fd00 = routable
- ✅ Easier troubleshooting (single BGP connection to monitor)
- ✅ Consistent with IPv6-first design philosophy
