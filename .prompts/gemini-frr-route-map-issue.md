# FRR Route-Map Configuration Issue: Multiple Match Statements Not Applying

## Goal

Prevent false ECMP (Equal-Cost Multi-Path) advertisement of a Talos Kubernetes API VIP (`fd00:101::10/128`) from non-owner Proxmox VE nodes to the edge router. The VIP is active on only ONE node (pve03) but is being advertised by ALL three PVE nodes due to iBGP route sharing, causing traffic to blackhole when the edge router selects a non-owner path.

## Current Issue

FRR 10.5.1 route-map configuration is not accepting multiple `match` statements within a single deny rule. When attempting to configure:

```
route-map RM_EDGE_EXPORT_V6 deny 5
 match large-community CL_K8S_PUBLIC
 match large-community CL_IBGP_LEARNED
exit
```

The running configuration only shows:

```
route-map RM_EDGE_EXPORT_V6 deny 5
 match large-community CL_IBGP_LEARNED
exit
```

The first match statement (`CL_K8S_PUBLIC`) is missing, causing the deny rule to filter ALL iBGP-learned routes instead of only those that are BOTH K8s public routes AND iBGP-learned.

## Architecture Context

### Network Topology

```
Edge Router (fd00:0:0:ffff::fffe)
    │
    ├─── PVE01 (10.10.0.1 / fd00:0:0:ffff::1) ────┐
    │                                               │
    ├─── PVE02 (10.10.0.2 / fd00:0:0:ffff::2) ─── iBGP Full Mesh
    │                                               │ ASN: 4200001000
    ├─── PVE03 (10.10.0.3 / fd00:0:0:ffff::3) ────┘
         │
         └── Talos nodes on fd00:101::/64 network
             ├── solcp01 (fd00:101::11) - Control Plane 1
             ├── solcp02 (fd00:101::12) - Control Plane 2
             ├── solcp03 (fd00:101::13) - Control Plane 3 [VIP OWNER]
             ├── solwk01 (fd00:101::21) - Worker 1
             ├── solwk02 (fd00:101::22) - Worker 2
             └── solwk03 (fd00:101::23) - Worker 3

VIP: fd00:101::10/128 (Talos Kubernetes API endpoint)
```

### BGP Configuration

**PVE Nodes (FRR 10.5.1)**:
- ASN: 4200001000
- iBGP full mesh between pve01, pve02, pve03
- VRF: vrf_evpnz1 for Talos cluster isolation
- Peer with Talos nodes via dynamic neighbor on fd00:101::/64

**Talos Nodes (bird2 v2.17.1)**:
- ASN: 42101010XX (unique per node)
- Each node peers with its local PVE node's VRF interface
- Advertise directly connected routes from ens18 interface (where VIP lives)
- Tag direct routes with BGP large community `4200001000:0:200` (CL_K8S_PUBLIC)

### Problem Flow

1. **VIP Active on solcp03**: The Talos VIP `fd00:101::10/128` is configured on solcp03's ens18 interface
2. **Bird2 Advertisement**: solcp03's bird2 advertises the VIP to pve03 with community `4200001000:0:200`
3. **iBGP Propagation**: pve03 imports the VIP into its BGP table and shares it with pve01/pve02 via iBGP
4. **Community Preservation**: iBGP preserves the `4200001000:0:200` community across all nodes
5. **False ECMP**: All three PVE nodes advertise the VIP to the edge router with identical communities
6. **Traffic Blackhole**: Edge router load-balances across all three paths, but only pve03 can forward (pve01/pve02 return "Address unreachable")

## Intended Solution

Tag all iBGP-learned routes with an additional community `4200001000:0:900` (CL_IBGP_LEARNED), then create a deny rule that filters routes matching BOTH:
- `4200001000:0:200` (CL_K8S_PUBLIC) - indicates route originated from Talos nodes
- `4200001000:0:900` (CL_IBGP_LEARNED) - indicates route was learned via iBGP

This creates a logical AND condition:
- Routes learned via iBGP from local VRF: Denied from edge export (prevent false ECMP)
- Routes imported directly from local VRF: Permitted to edge export (owner can advertise)

## FRR Configuration (Intended)

### Community Lists
```
bgp large-community-list standard CL_K8S_PUBLIC permit 4200001000:0:200
bgp large-community-list standard CL_IBGP_LEARNED permit 4200001000:0:900
```

### iBGP Inbound Route-Map (Tagging)
```
route-map RM_IBGP_IN permit 10
 set large-community 4200001000:0:900 additive
exit
```

### iBGP Neighbor Configuration
```
router bgp 4200001000
 neighbor IBGP peer-group
 neighbor IBGP remote-as 4200001000
 neighbor IBGP route-map RM_IBGP_IN in

 neighbor fd00:0:0:ffff::1 peer-group IBGP  # pve01
 neighbor fd00:0:0:ffff::2 peer-group IBGP  # pve02
 neighbor fd00:0:0:ffff::3 peer-group IBGP  # pve03
```

### Edge Export Route-Map (PROBLEM AREA)
```
route-map RM_EDGE_EXPORT_V6 deny 5
 match large-community CL_K8S_PUBLIC
 match large-community CL_IBGP_LEARNED
exit

route-map RM_EDGE_EXPORT_V6 permit 10
 ! Allow other routes
exit
```

**CRITICAL**: The deny rule needs BOTH match statements. The intended logic is:
- IF route has CL_K8S_PUBLIC AND route has CL_IBGP_LEARNED THEN deny
- ELSE continue to next rule

## Evidence of Issue

### 1. Template Configuration is Correct

File: `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2` (lines 151-154)

```jinja2
route-map RM_EDGE_EXPORT_V6 deny 5
 match large-community CL_K8S_PUBLIC
 match large-community CL_IBGP_LEARNED
exit
```

### 2. Running Configuration is Incomplete

Verification command:
```bash
ssh root@10.10.0.1 'vtysh -c "show run" | grep -A 5 "route-map RM_EDGE_EXPORT_V6 deny 5"'
```

Actual output:
```
route-map RM_EDGE_EXPORT_V6 deny 5
 match large-community CL_IBGP_LEARNED
exit
```

**Missing**: `match large-community CL_K8S_PUBLIC`

### 3. Edge Router Has 3 Paths (Should Be 1)

Verification command:
```bash
ssh admin@fd00:0:0:ffff::fffe '/ipv6/route/print where dst-address=fd00:101::10/128'
```

Output shows routes via all three PVE nodes:
```
DAb fd00:101::10/128  fd00:0:0:ffff::1  main  20  # pve01
DAb fd00:101::10/128  fd00:0:0:ffff::2  main  20  # pve02
DAb fd00:101::10/128  fd00:0:0:ffff::3  main  20  # pve03
```

Expected: Only one route via `fd00:0:0:ffff::3` (pve03, the VIP owner)

### 4. Community Tags are Correct on iBGP Routes

Verification on pve01 (non-owner):
```bash
ssh root@10.10.0.1 'vtysh -c "show bgp ipv6 fd00:101::10/128 json"' | jq '.paths[0].largeCommunity.list'
```

Output:
```json
["4200001000:0:200", "4200001000:0:900"]
```

This confirms:
- ✅ iBGP inbound route-map IS applying the CL_IBGP_LEARNED tag
- ✅ Original CL_K8S_PUBLIC community is preserved

### 5. All Nodes Advertising to Edge (Should Be Only Owner)

Verification command:
```bash
for pve in 10.10.0.1 10.10.0.2 10.10.0.3; do
  echo "=== PVE0${pve: -1} advertisements to edge ==="
  ssh root@$pve 'vtysh -c "show bgp ipv6 neighbors fd00:0:0:ffff::fffe advertised-routes"' | grep "fd00:101::10"
done
```

Result: All three nodes show the VIP in advertised routes

Expected: Only pve03 should advertise VIP

## Attempted Fixes (All Failed)

### Attempt 1: Re-apply route-map via vtysh
```bash
ssh root@10.10.0.1 'vtysh -c "conf t" \
  -c "route-map RM_EDGE_EXPORT_V6 deny 5" \
  -c "match large-community CL_K8S_PUBLIC" \
  -c "match large-community CL_IBGP_LEARNED" \
  -c "exit"'
```
Result: Only second match statement appears in running config

### Attempt 2: Delete and recreate
```bash
ssh root@10.10.0.1 'vtysh -c "conf t" \
  -c "no route-map RM_EDGE_EXPORT_V6 deny 5" \
  -c "route-map RM_EDGE_EXPORT_V6 deny 5" \
  -c "match large-community CL_K8S_PUBLIC" \
  -c "match large-community CL_IBGP_LEARNED" \
  -c "exit"'
```
Result: Same issue - only second match appears

### Attempt 3: Use heredoc with vtysh
```bash
ssh root@10.10.0.1 bash <<'EOF'
vtysh <<'VTYSH_EOF'
conf t
no route-map RM_EDGE_EXPORT_V6 deny 5
route-map RM_EDGE_EXPORT_V6 deny 5
 match large-community CL_K8S_PUBLIC
 match large-community CL_IBGP_LEARNED
exit
write memory
VTYSH_EOF
EOF
```
Result: User interrupted (previous attempts failed)

## Questions for Gemini

1. **Is FRR 10.5.1 route-map syntax correct for multiple match statements?**
   - Does FRR interpret multiple `match` lines as AND or OR logic?
   - Is there alternative syntax required for AND conditions?

2. **Why is only the second match statement persisting in the running config?**
   - Is this a bug in FRR 10.5.1?
   - Are community lists being treated differently than other match types?

3. **What is the correct way to configure "match both CL_K8S_PUBLIC AND CL_IBGP_LEARNED" in FRR?**
   - Should I use a combined community list?
   - Is there a different match syntax needed?
   - Example configuration snippet would be extremely helpful

4. **Alternative approaches to achieve the same filtering goal?**
   - Could I use route-map call or other mechanisms?
   - Is there a way to match on multiple communities in a single statement?

## System Information

- **FRR Version**: 10.5.1
- **Platform**: Proxmox VE 8.3
- **Deployment Method**: Ansible with Jinja2 template → `frr.conf`
- **Configuration Access**: vtysh CLI and direct file editing available
- **Verification Tools**: vtysh show commands, BGP table inspection, edge router route table

## Expected Success Criteria

After correct configuration:
1. ✅ Running config shows both match statements in deny rule
2. ✅ Edge router receives VIP route ONLY from pve03 (single path)
3. ✅ VIP is reachable from all networks
4. ✅ No "Address unreachable" errors from pve01/pve02
5. ✅ Kubernetes API responds successfully on VIP from external clients

## Additional Context

The template file (`frr-pve.conf.j2`) is deployed via Ansible and has been verified to contain the correct configuration with both match statements. The issue only appears when FRR loads the configuration into its running state. This suggests either:
- FRR configuration parser issue with multiple match statements
- Incorrect syntax for the intended AND logic
- Need for alternative configuration approach

The Ansible playbook completes without errors, indicating the file was successfully written to `/etc/frr/frr.conf` on all nodes and FRR was reloaded. However, the running configuration differs from the file contents.

## Proposed Solution (Hypothesis)

It is suspected that FRR `match` statements for the same attribute overwrite each other within a single route-map sequence. To implement AND logic for BGP communities, a single community list containing all required communities on the same line should be used.

**Proposed Config Change:**
```
bgp large-community-list standard CL_K8S_PUBLIC_AND_IBGP permit 4200001000:0:200 4200001000:0:900

route-map RM_EDGE_EXPORT_V6 deny 5
 match large-community CL_K8S_PUBLIC_AND_IBGP
exit
```
