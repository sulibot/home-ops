# RouterOS Configuration - Phase 1 Infrastructure Loopback Updates

## Overview

Update RouterOS (MikroTik edge router) configuration to use new infrastructure loopback addressing scheme.

**Critical**: This is dual-addressing. Add new addresses alongside old ones, verify BGP sessions establish, then remove old addresses.

---

## Current Configuration (Before Changes)

### Current Loopback Addresses
- IPv4: `10.255.255.254/32`
- IPv6: `fd00:0:0:ffff::fffe/128`

### Current BGP Peers
- pve01: `fd00:0:0:ffff::1` (IPv6), `10.255.0.1` (IPv4)
- pve02: `fd00:0:0:ffff::2` (IPv6), `10.255.0.2` (IPv4)
- pve03: `fd00:0:0:ffff::3` (IPv6), `10.255.0.3` (IPv4)

---

## Step 1: Add New Loopback Addresses (Dual Addressing)

```routeros
# Verify current loopback interface exists
/interface/bridge print where name=loopback

# Add new IPv4 loopback address (alongside old)
/ip/address add address=10.255.0.254/32 interface=loopback comment="New infrastructure loopback - Phase 1"

# Add new IPv6 loopback address (alongside old)
/ipv6/address add address=fd00:0:0:ffff::fffe/128 interface=loopback comment="New infrastructure loopback - Phase 1"

# Verify both old and new addresses are configured
/ip/address print where interface=loopback
# Should show both: 10.255.255.254/32 and 10.255.0.254/32

/ipv6/address print where interface=loopback
# Should show both: fd00:0:0:ffff::fffe/128 and fd00:0:0:ffff::fffe/128
```

---

## Step 2: Update OSPF Configuration

### OSPFv2 (IPv4)

```routeros
# The IPv4 loopback is already using 10.255.0.0/24 range, just add new address
# OSPF should automatically advertise both addresses

# Verify OSPF is advertising both loopbacks
/routing/ospf/instance print
/routing/ospf/interface-template print

# Check OSPF routes
/routing/route print where ospf
```

### OSPFv3 (IPv6)

```routeros
# Update OSPFv3 to advertise new infrastructure prefix

# Check current OSPFv3 configuration
/routing/ospf/instance print where version=3
/routing/ospf/area print

# Ensure fd00:0:0:ffff::/64 is included in OSPF area
# This should happen automatically if loopback is in OSPFv3 area

# Verify OSPFv3 is advertising new prefix
/ipv6/route print where ospf
```

---

## Step 3: Update BGP Peer Configuration

### Update BGP Connections to Use New Loopback as Update-Source

```routeros
# List current BGP connections
/routing/bgp/connection print detail

# Update each PVE peer to use new loopback addresses
# NOTE: These commands assume connection names. Adjust based on your config.

# For IPv6 BGP sessions:
/routing/bgp/connection
  set [find remote.address=fd00:0:0:ffff::1] local.address=fd00:0:0:ffff::fffe
  set [find remote.address=fd00:0:0:ffff::2] local.address=fd00:0:0:ffff::fffe
  set [find remote.address=fd00:0:0:ffff::3] local.address=fd00:0:0:ffff::fffe

# For IPv4 BGP sessions:
/routing/bgp/connection
  set [find remote.address=10.255.0.1] local.address=10.255.0.254
  set [find remote.address=10.255.0.2] local.address=10.255.0.254
  set [find remote.address=10.255.0.3] local.address=10.255.0.254
```

### Alternative: Update by Connection Name

If your connections are named (recommended approach):

```routeros
/routing/bgp/connection print
# Note the names: e.g., bgp-pve01-v6, bgp-pve01-v4, etc.

# Update IPv6 connections
/routing/bgp/connection
  set bgp-pve01-v6 local.address=fd00:0:0:ffff::fffe
  set bgp-pve02-v6 local.address=fd00:0:0:ffff::fffe
  set bgp-pve03-v6 local.address=fd00:0:0:ffff::fffe

# Update IPv4 connections
/routing/bgp/connection
  set bgp-pve01-v4 local.address=10.255.0.254
  set bgp-pve02-v4 local.address=10.255.0.254
  set bgp-pve03-v4 local.address=10.255.0.254
```

---

## Step 4: Update BGP Router-ID (if needed)

```routeros
# Check current BGP instance router-id
/routing/bgp/template print

# If router-id is using old address, update it
/routing/bgp/template
  set default router-id=10.255.0.254

# Note: Router-ID change will reset all BGP sessions
```

---

## Step 5: Verification

### Verify Loopback Addresses

```routeros
# Check both IPv4 addresses are present
/ip/address print where interface=loopback
# Expected:
# - 10.255.255.254/32 (old)
# - 10.255.0.254/32 (new)

# Check both IPv6 addresses are present
/ipv6/address print where interface=loopback
# Expected:
# - fd00:0:0:ffff::fffe/128 (old)
# - fd00:0:0:ffff::fffe/128 (new)
```

### Verify OSPF Adjacencies

```routeros
# OSPFv2 neighbors
/routing/ospf/neighbor print

# OSPFv3 neighbors
/routing/ospf/neighbor print where instance~"v3"

# Check OSPF routes include new prefixes
/routing/route print where ospf and dst-address~"10.255.0"
/ipv6/route print where ospf and dst-address~"fd00:0:0:ffff"
```

### Verify BGP Sessions

```routeros
# Check all BGP sessions are ESTABLISHED
/routing/bgp/session print status
# All sessions should show: state=established

# Check BGP session details for each peer
/routing/bgp/session print detail where remote.address=fd00:0:0:ffff::1
/routing/bgp/session print detail where remote.address=fd00:0:0:ffff::2
/routing/bgp/session print detail where remote.address=fd00:0:0:ffff::3

# Verify local address is using new loopback
# local.address should be: fd00:0:0:ffff::fffe (IPv6) or 10.255.0.254 (IPv4)
```

### Verify Route Exchange

```routeros
# Check routes received from PVE nodes
/routing/route print where bgp and received-from~"fd00:0:0:ffff"

# Check IPv4 routes
/routing/route print where bgp and dst-address~"10.101.0.0/24"

# Check IPv6 routes
/ipv6/route print where bgp and dst-address~"fd00:101"
```

---

## Step 6: Traffic Verification

```routeros
# Ping PVE nodes using new loopback addresses
/ping fd00:0:0:ffff::1 count=5
/ping fd00:0:0:ffff::2 count=5
/ping fd00:0:0:ffff::3 count=5
/ping 10.255.0.1 count=5
/ping 10.255.0.2 count=5
/ping 10.255.0.3 count=5

# Traceroute to verify routing paths
/tool/traceroute fd00:101::6 count=1
# Should route through PVE BGP next-hops

# Test DNS resolution using new DNS server address
/tool/dns-lookup google.com server=fd00:0:0:ffff::53
```

---

## Step 7: Monitor for Issues

```routeros
# Monitor BGP session state changes
/log print where topics~"bgp"

# Monitor OSPF state changes
/log print where topics~"ospf"

# Check for any routing loops or issues
/routing/route print where invalid
```

---

## Rollback Procedure

If BGP sessions fail to establish or routing issues occur:

```routeros
# Revert BGP connections to old loopback addresses
/routing/bgp/connection
  set [find remote.address=fd00:0:0:ffff::1] local.address=fd00:0:0:ffff::fffe
  set [find remote.address=fd00:0:0:ffff::2] local.address=fd00:0:0:ffff::fffe
  set [find remote.address=fd00:0:0:ffff::3] local.address=fd00:0:0:ffff::fffe

# For IPv4:
/routing/bgp/connection
  set [find remote.address=10.255.0.1] local.address=10.255.255.254
  set [find remote.address=10.255.0.2] local.address=10.255.255.254
  set [find remote.address=10.255.0.3] local.address=10.255.255.254

# Wait for sessions to re-establish
/routing/bgp/session print status
```

---

## Post-Verification: Remove Old Addresses

**Only after Phase 1 is fully stable and verified (minimum 24-48 hours)**:

```routeros
# Remove old IPv4 loopback
/ip/address remove [find address=10.255.255.254/32 and interface=loopback]

# Remove old IPv6 loopback
/ipv6/address remove [find address=fd00:0:0:ffff::fffe/128 and interface=loopback]

# Verify only new addresses remain
/ip/address print where interface=loopback
# Should only show: 10.255.0.254/32

/ipv6/address print where interface=loopback
# Should only show: fd00:0:0:ffff::fffe/128
```

---

## Configuration Backup

**Before making any changes**:

```routeros
# Export current configuration
/export file=backup-before-phase1-$(date +%Y%m%d)

# Verify backup was created
/file print where name~"backup"
```

**After successful deployment**:

```routeros
# Export new configuration
/export file=phase1-deployed-$(date +%Y%m%d)
```

---

## Example Complete Configuration Snippet

Based on typical RouterOS v7 BGP configuration:

```routeros
# Add new loopback addresses
/ip/address
add address=10.255.0.254/32 interface=loopback comment="Infrastructure loopback v2"

/ipv6/address
add address=fd00:0:0:ffff::fffe/128 interface=loopback comment="Infrastructure loopback v2"

# Update BGP template (if needed)
/routing/bgp/template
set default router-id=10.255.0.254

# Update BGP connections
/routing/bgp/connection
# PVE01 IPv6
set [find name=bgp-pve01-v6] \
  local.role=ebgp \
  local.address=fd00:0:0:ffff::fffe \
  remote.address=fd00:0:0:ffff::1 \
  multihop=yes \
  router-id=10.255.0.254

# PVE01 IPv4
set [find name=bgp-pve01-v4] \
  local.role=ebgp \
  local.address=10.255.0.254 \
  remote.address=10.255.0.1 \
  multihop=yes \
  router-id=10.255.0.254

# Repeat for pve02, pve03...
```

---

## Verification Checklist

- [ ] Backup configuration exported
- [ ] New loopback addresses added (dual addressing)
- [ ] OSPF adjacencies stable
- [ ] BGP connections updated to use new local addresses
- [ ] All BGP sessions ESTABLISHED
- [ ] Routes received from all PVE nodes
- [ ] Traffic flows correctly (ping, traceroute tests pass)
- [ ] DNS resolution working
- [ ] No log errors related to BGP or OSPF
- [ ] Wait 24-48 hours for stability verification
- [ ] Old addresses removed after verification period

---

## Troubleshooting

### BGP Sessions Not Establishing

```routeros
# Check connection state
/routing/bgp/connection print detail

# Check session state and last error
/routing/bgp/session print status

# Verify IP connectivity to new loopbacks
/ping fd00:0:0:ffff::1 source=fd00:0:0:ffff::fffe

# Check firewall rules aren't blocking BGP (TCP 179)
/ip/firewall/filter print where protocol=tcp and dst-port=179
```

### Routes Not Being Exchanged

```routeros
# Check BGP output filters
/routing/filter/rule print where chain~"bgp"

# Verify address families are enabled
/routing/bgp/connection print detail
# Should show: address-families=ip,ipv6

# Check route import/export policies
/routing/bgp/connection print detail where remote.address~"fd00:0:0:ffff"
```

---

*Generated for Phase 1 RouterOS deployment - 2025-12-28*
