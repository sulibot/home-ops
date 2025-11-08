# ROS BGP Configuration Changes Needed

## Current Configuration
```
ebgp6-in-v101:
  remote.address=fd00:255:101::/64
  local.address=fd00:255::fffe

ebgp6-cilium-101:
  remote.address=fd00:101::/64
  local.address=fd00:255::fffe
```

## Required Changes

### 1. Keep ebgp6-in-v101 for FRR (NO CHANGES)
- Purpose: Accept BGP from FRR on K8s VMs
- Source: fd00:255:101::11 (FRR loopback)
- Peer: fd00:255::fffe (ROS edge loopback) → fd00:101::fffe (ROS vlan101 interface)

**WAIT - this is wrong. FRR will peer with fd00:101::fffe, not fd00:255::fffe**

Let me reconsider...

### Updated Understanding

**FRR Configuration:**
- Source: fd00:255:101::11 (loopback)
- Peer: fd00:101::fffe (ROS vlan101 interface)
- ROS sees connection FROM fd00:255:101::11 TO fd00:101::fffe

**Cilium Configuration:**
- Source: fc00:255:101::11 (loopback)
- Peer: fd00:101::fffe (ROS vlan101 interface)
- ROS sees connection FROM fc00:255:101::11 TO fd00:101::fffe

**ROS BGP Connections Needed:**

Both connections will have `local.address=fd00:101::fffe` since both FRR and Cilium peer with this address.

### Connection 1: ebgp6-in-v101 (FRR)
```
/routing/bgp/connection/set [find name="ebgp6-in-v101"] \
  remote.address=fd00:255:101::/64 \
  local.address=fd00:101::fffe
```

### Connection 2: ebgp6-cilium-101 (Cilium)
```
/routing/bgp/connection/set [find name="ebgp6-cilium-101"] \
  remote.address=fc00:255:101::/64 \
  local.address=fd00:101::fffe
```

## Summary
- Both connections listen on fd00:101::fffe (ROS vlan101 interface)
- ebgp6-in-v101 accepts from fd00:255:101::/64 (FRR loopback subnet)
- ebgp6-cilium-101 accepts from fc00:255:101::/64 (Cilium loopback subnet)
- No overlap, clean separation

## Static Routes Required

The following static routes must be configured on ROS to make the loopback IPs reachable.
These routes direct traffic to the loopback IPs via the nodes' interface IPs.

### FRR Loopback Routes (fd00:255:101::/64)

```
/ipv6/route/add dst-address=fd00:255:101::11/128 gateway=fd00:101::11
/ipv6/route/add dst-address=fd00:255:101::12/128 gateway=fd00:101::12
/ipv6/route/add dst-address=fd00:255:101::13/128 gateway=fd00:101::13
/ipv6/route/add dst-address=fd00:255:101::21/128 gateway=fd00:101::21
/ipv6/route/add dst-address=fd00:255:101::22/128 gateway=fd00:101::22
/ipv6/route/add dst-address=fd00:255:101::23/128 gateway=fd00:101::23
```

### Cilium Loopback Routes (fc00:255:101::/64)

```
/ipv6/route/add dst-address=fc00:255:101::11/128 gateway=fd00:101::11
/ipv6/route/add dst-address=fc00:255:101::12/128 gateway=fd00:101::12
/ipv6/route/add dst-address=fc00:255:101::13/128 gateway=fd00:101::13
/ipv6/route/add dst-address=fc00:255:101::21/128 gateway=fd00:101::21
/ipv6/route/add dst-address=fc00:255:101::22/128 gateway=fd00:101::22
/ipv6/route/add dst-address=fc00:255:101::23/128 gateway=fd00:101::23
```

## Verification

After applying the configuration, verify with:

```
# Check BGP connections
/routing/bgp/connection/print detail

# Check BGP sessions
/routing/bgp/session/print

# Check static routes
/ipv6/route/print where dst-address~"255:101"

# Monitor BGP neighbor establishment
/routing/bgp/session/monitor
```

## Configuration Persistence

All commands above are automatically persisted in ROS configuration. To backup:

```
/export file=bgp-dual-stack-backup
```
