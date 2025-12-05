# BGP Route Reflection with allowas-in Solution

## Problem Statement

CoreDNS pods were stuck at 0/1 Ready for extended periods (3-7 hours) due to networking failure between Kubernetes nodes.

### Root Cause

**BGP AS_PATH Loop Prevention Blocking Route Reflection**

The cluster topology uses:
- 6 Talos nodes (3 control plane, 3 workers) in AS 65101
- Each node advertises its /128 loopback (fd00:255:101::XX/128) via BGP
- RouterOS (AS 65000) acts as route reflector
- All nodes peer with RouterOS using eBGP

**The Issue:**
1. Node A (AS 65101) advertises `fd00:255:101::11/128` → RouterOS (AS 65000)
2. RouterOS receives the route and tries to reflect it to Node B (AS 65101)
3. The AS_PATH becomes: `65101 → 65000`
4. Node B sees its own ASN (65101) in the AS_PATH and **rejects the route** due to BGP loop prevention
5. Without routes to other nodes' loopbacks, Cilium cannot install direct node routes
6. Pod-to-pod networking fails, preventing CoreDNS from starting

### Symptoms

- CoreDNS pods: 0/1 Ready (Running but not passing readiness checks)
- Cilium logs: "Unable to install direct node route" errors
- Each node only has a route to its own /128 loopback
- No routes to other nodes' loopbacks in kernel routing table
- RouterOS has all 6 loopback routes but doesn't advertise them back

## Solution

### BGP allowas-in Configuration

The `allowas-in` BGP feature disables AS_PATH loop prevention, allowing a BGP speaker to accept routes that contain its own ASN in the AS_PATH.

**Configuration Added to FRR:**

```jinja2
router bgp {{ bgp.upstream.local_asn }}
 address-family ipv4 unicast
  neighbor {{ peer.address }} activate
  neighbor {{ peer.address }} allowas-in
 exit-address-family

 address-family ipv6 unicast
  neighbor {{ peer.address }} activate
  neighbor {{ peer.address }} allowas-in
 exit-address-family
```

This was added to the FRR extension's `frr.conf.j2` template for both IPv4 and IPv6 BGP neighbors.

### Implementation Steps

1. **Forked FRR Extension**
   - Forked from `ghcr.io/jsenecal/frr-talos-extension`
   - Created fork at `ghcr.io/sulibot/frr-talos-extension`

2. **Added allowas-in to FRR Configuration**
   - Modified `frr.conf.j2` template
   - Added `neighbor allowas-in` for both IPv4 and IPv6 address families
   - Lines 281 (IPv4) and 314 (IPv6) in frr.conf.j2

3. **Enhanced Monitoring** (Bonus Features)
   - Changed monitoring interval from 1 min to 5 min
   - Added clear section headers for grep-ability
   - Enhanced BGP diagnostics output
   - Added routes advertised/received reporting

4. **Built Custom Talos Installer**
   ```bash
   cd terraform/infra/live/cluster-101/1-talos-install-image-build
   terragrunt apply -auto-approve
   ```
   - Built custom installer with updated FRR extension
   - Image: `ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0-beta.0`

5. **Rebuilt Cluster**
   - Destroyed existing cluster
   - Regenerated machine configs
   - Bootstrapped cluster with new installer containing allowas-in

## Results

### ✅ Verified Working

**1. Node Routes (Before vs After)**

Before (broken):
```bash
# Node 11 only had its own loopback
fd00:255:101::11/128 via 0.0.0.0 dev dummy0
```

After (working):
```bash
# Node 11 has routes to ALL nodes' loopbacks
fd00:255:101::11/128 via 0.0.0.0 dev dummy0
fd00:255:101::12/128 via 0.0.0.0 dev ens18
fd00:255:101::13/128 via 0.0.0.0 dev ens18
fd00:255:101::21/128 via 0.0.0.0 dev ens18
fd00:255:101::22/128 via 0.0.0.0 dev ens18
fd00:255:101::23/128 via 0.0.0.0 dev ens18
```

**2. CoreDNS Status**

Before:
```
coredns-5dc8cf9484-j4rdk   0/1   Running   0   3h31m
coredns-5dc8cf9484-qzq5h   0/1   Running   5   7h2m
```

After:
```
coredns-5dc8cf9484-8l5fq   1/1   Running   0   9m42s
coredns-5dc8cf9484-tnjh5   1/1   Running   0   9m42s
```

**3. Cilium Status**

Before: "Unable to install direct node route" errors

After:
```
Cilium Status: OK
All 6 Cilium pods: Running
0 routing errors in last 5 minutes
```

**4. BGP Configuration Verification**

```bash
talosctl logs ext-frr | grep allowas-in
# Output:
neighbor 10.0.101.254 allowas-in
neighbor fd00:101::fffe allowas-in
```

## Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    RouterOS (AS 65000)                      │
│                 fd00:101::fffe / 10.0.101.254               │
│                    (Route Reflector)                        │
└─────────────────────────────────────────────────────────────┘
         ▲                    ▲                    ▲
         │ eBGP               │ eBGP               │ eBGP
         │                    │                    │
    ┌────┴────┐          ┌────┴────┐          ┌────┴────┐
    │ solcp01 │          │ solcp02 │          │ solcp03 │
    │ AS65101 │          │ AS65101 │          │ AS65101 │
    │ ::11/128│          │ ::12/128│          │ ::13/128│
    └─────────┘          └─────────┘          └─────────┘

    ┌─────────┐          ┌─────────┐          ┌─────────┐
    │ solwk01 │          │ solwk02 │          │ solwk03 │
    │ AS65101 │          │ AS65101 │          │ AS65101 │
    │ ::21/128│          │ ::22/128│          │ ::23/128│
    └─────────┘          └─────────┘          └─────────┘
```

**Route Flow:**
1. Each node advertises its /128 loopback to RouterOS
2. RouterOS (with `output.redistribute=bgp`) reflects routes to all peers
3. Nodes receive routes with AS_PATH: `65101 → 65000`
4. With `allowas-in`, nodes accept these routes despite seeing their own ASN
5. Kernel routing table gets populated with routes to all node loopbacks
6. Cilium can now install direct node routes
7. Pod-to-pod networking works

## Files Modified

### FRR Extension Repository
- `frr.conf.j2` - Added allowas-in configuration (lines 281, 314)
- `docker-start` - Enhanced monitoring (lines 162-239)
- `Dockerfile` - Added diagnostic scripts directory
- `.github/workflows/build-and-push.yaml` - Fixed GHCR authentication

### Home-Ops Repository
- `terraform/infra/live/cluster-101/1-talos-install-image-build/terragrunt.hcl` - Updated to use forked FRR extension

### Commits
- FRR extension: `e667628` (allowas-in), `a1a18e7` (monitoring), `cd3bdf6` (workflow)
- Home-ops: `f14d1985` (use fork), `a468e861` (update secrets)

## Alternative Solutions Considered

### 1. iBGP Full Mesh Between Nodes
**Rejected**: Would require n(n-1)/2 BGP sessions (15 for 6 nodes), complex configuration, and wouldn't leverage existing RouterOS infrastructure.

### 2. RouterOS as-override
**Not Needed**: This would replace the peer ASN in AS_PATH. We chose `allowas-in` on FRR nodes as it's more standard and explicit.

### 3. Different ASN per Node
**Rejected**: Would break the design intent of having all cluster nodes in the same ASN. Also creates routing complexity.

## Best Practices

### When to Use allowas-in
- Route reflection scenarios with same ASN peers
- eBGP peering through a route reflector
- When you control both sides of the peering and understand the loop implications

### Security Considerations
- Only use with trusted peers
- Ensure your network design prevents actual routing loops
- Monitor BGP route counts for anomalies
- Consider using `allowas-in 1` (limit to 1 occurrence) instead of unlimited

### Monitoring
Check BGP route acceptance:
```bash
talosctl logs ext-frr | grep "BGP Summary" -A 20
```

Verify kernel routes:
```bash
talosctl read /proc/net/ipv6_route | grep fd00025501
```

## Troubleshooting

### Routes Not Being Installed
1. Check BGP sessions are established:
   ```bash
   talosctl logs ext-frr | grep Established
   ```

2. Verify allowas-in is configured:
   ```bash
   talosctl logs ext-frr | grep allowas-in
   ```

3. Check RouterOS is advertising routes:
   ```bash
   ssh admin@routeros "/routing/bgp/advertisements/print"
   ```

### Cilium Still Showing Errors
1. Verify routes exist in kernel:
   ```bash
   talosctl read /proc/net/ipv6_route | grep fd00025501 | wc -l
   # Should show 7 (6 nodes + 1 duplicate entry)
   ```

2. Check Cilium status:
   ```bash
   kubectl -n kube-system exec ds/cilium -- cilium status
   ```

## References

- [BGP allowas-in - Cisco Documentation](https://www.cisco.com/c/en/us/td/docs/ios-xml/ios/iproute_bgp/command/irg-cr-book/bgp-a1.html#wp3012110686)
- [FRRouting BGP Configuration](http://docs.frrouting.org/en/latest/bgp.html)
- [BGP Route Reflection - RFC 4456](https://datatracker.ietf.org/doc/html/rfc4456)
- [MikroTik RouterOS BGP](https://help.mikrotik.com/docs/spaces/ROS/pages/328220/BGP)
- [Talos System Extensions](https://www.talos.dev/latest/talos-guides/configuration/system-extensions/)

## Appendix: Diagnostic Scripts

The updated FRR extension includes diagnostic scripts in `/usr/local/bin/frr-scripts/`:

- **bgp-summary** - Show BGP summary for all VRFs
- **bgp-neighbors** - Show detailed BGP neighbor information
- **bgp-routes-adv** - Show routes advertised to BGP neighbors
- **bgp-routes-recv** - Show routes received from BGP neighbors
- **show-config** - Show current FRR running configuration
- **route-summary** - Show routing table summary
- **bfd-status** - Show BFD session status
- **bgp-full-status** - Comprehensive BGP status report

Usage:
```bash
talosctl read /usr/local/bin/frr-scripts/bgp-summary
```

Note: These scripts are included in `ghcr.io/sulibot/frr-talos-extension:latest` built after 2025-12-05.
