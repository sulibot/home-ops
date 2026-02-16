# BGP Pod CIDR Routing Failure - FRR Route-Map Analysis

## Problem Statement

Pod-to-pod connectivity is broken in a Talos Kubernetes cluster using Cilium CNI with BGP-based routing. Cilium cluster health shows **1/6 nodes reachable** (only localhost), preventing cross-node pod communication.

**Environment:**
- **Platform:** Talos v1.12.1, Kubernetes v1.34.1
- **CNI:** Cilium v1.18.6 with BGP Control Plane enabled
- **Routing:** BGP via bird2 (on Talos nodes) → FRRouting 10.5.1 (on Proxmox VE)
- **Configuration:** `autoDirectNodeRoutes: false` (BGP-based routing, not Cilium auto-direct)

## Current BGP Architecture

```
┌─────────────────────────────────────────────────────┐
│ Cilium BGP Control Plane (each Talos node)         │
│ ASN: 4220101000 (cluster-wide)                     │
│ Advertises: Pod CIDRs, LoadBalancer VIPs           │
└───────────────┬─────────────────────────────────────┘
                │ Localhost peering (::1:179)
                │
┌───────────────┴─────────────────────────────────────┐
│ bird2 v2.17.1 (Talos ExtensionServiceConfig)       │
│ ASN: 42101010XX (per-node unique)                   │
│ Receives: Pod CIDRs from Cilium                     │
│ Should export: Pod CIDRs to FRR                     │
└───────────────┬─────────────────────────────────────┘
                │ BGP over fd00:101::/64
                │
┌───────────────┴─────────────────────────────────────┐
│ FRRouting (Proxmox VE) - VRF vrf_evpnz1             │
│ ASN: 4200001000                                     │
│ Peer-group: VMS (dynamic neighbors on fd00:101::/64)│
│ Should receive: Pod CIDRs from bird2                │
│ Should propagate: Via iBGP to all PVE nodes         │
└─────────────────────────────────────────────────────┘
```

## Network Addressing

- **Node IPs:** `fd00:101::11-13` (control plane), `fd00:101::21-23` (workers)
- **Pod CIDR Range:** `fd00:101:224::/60` (subdivided into /64 per node)
  - solcp01: `fd00:101:224::/64`
  - solcp02: `fd00:101:224:1::/64`
  - solwk01: `fd00:101:224:2::/64`
  - solwk02: `fd00:101:224:3::/64`
  - solwk03: `fd00:101:224:4::/64`
  - solcp03: `fd00:101:224:5::/64`
- **Loopbacks:** `fd00:101:fe::/64` (per-node /128)
- **Kubernetes API VIP:** `fd00:101::10/128`

## Diagnostic Evidence

### 1. Cilium BGP Status

```bash
$ kubectl get ciliumbgpnodeconfig -o yaml | grep -A 20 "peerAddress: ::1"
peerAddress: ::1
peeringState: established
routeCount:
  - advertised: 1  # Advertising local pod CIDR
    afi: ipv6
    received: 0    # ← PROBLEM: Not receiving other nodes' pod CIDRs
    safi: unicast
```

**Interpretation:**
- Cilium → bird2 BGP session is **established**
- Cilium **advertises** its local pod CIDR to bird2
- Cilium **receives 0 routes** from bird2 (should receive ~5 from other nodes)

### 2. Cilium Advertised Routes

```bash
$ kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp routes advertised ipv6 unicast
VRouter      Peer   Prefix              NextHop   Age        Attrs
4220101000   ::1    fd00:101:224::/64   ::1       2h23m12s   [{Origin: i} ...]
```

**Interpretation:**
- Cilium correctly advertises `fd00:101:224::/64` (solcp01's pod CIDR) to bird2

### 3. FRR BGP Table (Proxmox VE)

```bash
$ ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 unicast"'
     Network          Next Hop            Metric LocPrf Weight Path
 *>  fd00:101::10/128 fe80::be24:11ff:fe7e:d43c   0      4210101011 i
 *>  fd00:101:fe::11/128
                      fe80::be24:11ff:fe7e:d43c   0      4210101011 i
 *>  fd00:101:fe::21/128
                      fe80::be24:11ff:feb1:3ce7   0      4210101021 i
 *>  fd00:101:fe::41/128
                      fe80::be24:11ff:fe75:bb1    0      4210101041 i
```

**Interpretation:**
- FRR receives Kubernetes API VIP (`fd00:101::10/128`) ✅
- FRR receives loopbacks (`fd00:101:fe::/64`) ✅
- FRR **does NOT receive any pod CIDRs** (`fd00:101:224::/60`) ❌

### 4. FRR BGP Summary

```bash
$ ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 unicast summary"'
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd
*fd00:101::11   4 4210101011       513       445       44    0    0 02:26:28            4
*fd00:101::21   4 4210101021       511       445       44    0    0 02:26:31            3
*fd00:101::41   4 4210101041      3923      3442       44    0    0 19:04:49            1
```

**Interpretation:**
- BGP sessions are **established** with all Talos nodes
- PfxRcd shows 4, 3, 1 prefixes received (loopbacks + VIP, NOT pod CIDRs)

### 5. Cilium Cluster Health

```bash
$ kubectl exec -n kube-system ds/cilium -- cilium-dbg status --verbose | grep "Cluster health"
Cluster health:   1/6 reachable
```

**Interpretation:**
- Only localhost (solcp01) is reachable from solcp01
- All other 5 nodes are unreachable (no BGP-learned routes for their pod CIDRs)

### 6. Kernel Routing Table (Talos Node)

```bash
$ talosctl -n fd00:101::11 get routes | grep "fd00:101:224"
fd00:101:224::/64       cilium_host       1024  # Local pod CIDR only
```

**Interpretation:**
- Only the **local** pod CIDR is present
- No routes to other nodes' pod CIDRs (expected via BGP)

## Configuration Analysis

### FRR Configuration (Proxmox VE)

**File:** `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

**Prefix-Lists Defined:**
```
ipv6 prefix-list PL_K8S_PODS_V6 seq 5 permit fd00:101:224::/60 le 64  ✅ EXISTS
ipv6 prefix-list PL_K8S_LOOPBACKS_V6 seq 5 permit fd00:101:fe::/64 le 128
ipv6 prefix-list PL_TENANT_V6 seq 20 permit fd00:101::/48 le 128
```

**Inbound Route-Map for VMS (Talos nodes):**
```
route-map RM_VMS_IN_V6 permit 10
 match ipv6 address prefix-list PL_TENANT_V6
exit
!
route-map RM_VMS_IN_V6 permit 15
 match ipv6 address prefix-list PL_TENANT_GUA_V6
exit
!
route-map RM_VMS_IN_V6 permit 20
 match ipv6 address prefix-list PL_K8S_LOOPBACKS_V6  ← Only loopbacks
exit
!
route-map RM_VMS_IN_V6 deny 999  ← BLOCKS everything else (including pod CIDRs!)
exit
```

**Applied to Peers:**
```
neighbor VMS route-map RM_VMS_IN_V6 in
bgp listen range fd00:101::/64 peer-group VMS
```

### bird2 Configuration (Talos Nodes)

**File:** `terraform/infra/modules/talos_config/main.tf` (lines 388-450)

**Cilium BGP Peering (localhost ::1):**
```bird
protocol bgp cilium {
  description "Cilium BGP Control Plane";
  local as 4210101011;
  neighbor ::1 as 4220101000;

  ipv4 {
    import all;
    export none;  # One-way: Cilium → bird2
  };

  ipv6 {
    import all;
    export none;  # One-way: Cilium → bird2
  };
}
```

**Upstream FRR Peering:**
```bird
protocol bgp upstream {
  description "PVE ULA Anycast Gateway";
  local as 4210101011;
  neighbor fd00:101::fffe as 4200001000;

  ipv4 {
    import all;
    export filter {
      # Tag loopbacks from direct protocol
      if proto = "direct_routes" then {
        bgp_large_community.add((4200001000, 0, 200));
        accept;
      }
      # Pass through other routes (e.g. from Cilium)
      accept;  ← Should export pod CIDRs to FRR
    };
  };

  ipv6 {
    import filter {
      # Reject local node subnet /64
      if net = fd00:101::/64 then reject;
      accept;
    };
    export filter {
      # Tag loopbacks from direct protocol
      if proto = "direct_routes" then {
        bgp_large_community.add((4200001000, 0, 200));
        accept;
      }
      # Pass through other routes (e.g. from Cilium)
      accept;  ← Should export pod CIDRs to FRR
    };
  };
}
```

### Cilium BGP Advertisement

**File:** `kubernetes/apps/networking/cilium/bgp/cilium-bgp-config.yaml`

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: pod-cidr
  labels:
    advertise: "bgp"
spec:
  advertisements:
  - advertisementType: "PodCIDR"
    attributes:
      communities:
        large: ["4200001000:0:100"]  # K8S_INTERNAL community
```

## Root Cause Analysis

**Hypothesis:** FRR inbound route-map `RM_VMS_IN_V6` is **blocking pod CIDRs** from Talos nodes because:

1. ✅ **Prefix-list exists:** `PL_K8S_PODS_V6` correctly defines `fd00:101:224::/60 le 64`
2. ❌ **Route-map does NOT use it:** `RM_VMS_IN_V6` only permits:
   - `PL_TENANT_V6` (general tenant networks + loopbacks)
   - `PL_TENANT_GUA_V6` (GUA addresses)
   - `PL_K8S_LOOPBACKS_V6` (loopbacks only)
3. ❌ **Missing permit rule:** No `permit 25 match ipv6 address prefix-list PL_K8S_PODS_V6`
4. ❌ **Explicit deny:** Rule 999 denies everything else, blocking pod CIDRs

**Evidence Supporting Hypothesis:**
- bird2 export filter permits ALL routes (line 426/446: `accept;`)
- FRR receives loopbacks ✅ (matches `PL_K8S_LOOPBACKS_V6`)
- FRR receives VIP ✅ (matches `PL_TENANT_V6` via fd00:101::/48)
- FRR does NOT receive pod CIDRs ❌ (blocked by deny 999)

## Questions for Validation

1. **Is the root cause analysis correct?**
   - Does the missing route-map permit rule explain why pod CIDRs are blocked?
   - Are there any other potential causes I'm missing?

2. **What is the correct fix?**
   - Should `RM_VMS_IN_V6` include a permit rule for `PL_K8S_PODS_V6`?
   - What sequence number should it use (before deny 999)?
   - Should it include any additional filtering or community tagging?

3. **Secondary issue: bird2 → Cilium export**
   - After FRR accepts pod CIDRs, does bird2 need to export them back to Cilium?
   - Current config: `export none` (one-way Cilium → bird2)
   - Should it be changed to export routes from "upstream" protocol back to Cilium?

4. **BGP Large Communities**
   - Cilium tags pod CIDRs with `4200001000:0:100` (K8S_INTERNAL)
   - Should the FRR route-map filter or tag based on this community?
   - Should pod CIDRs be tagged differently for iBGP propagation vs edge export?

5. **Expected Route Flow (After Fix)**
   ```
   1. Cilium (solcp02) advertises fd00:101:224:1::/64 → bird2
   2. bird2 exports to FRR (via "upstream" BGP) ← Currently blocked here
   3. FRR accepts (new permit rule for PL_K8S_PODS_V6)
   4. FRR propagates via iBGP to all PVE nodes
   5. All nodes' bird2 receive other pod CIDRs from FRR
   6. bird2 exports back to Cilium (if bidirectional peering enabled)
   7. Cilium installs routes for cross-node pod traffic
   ```

   Is this the correct flow? What changes are needed?

## Implemented Fix (Needs Validation)

Based on Gemini's analysis, the following changes have been implemented:

### Change 1: Cilium BGP Advertisements

**File:** `kubernetes/apps/networking/cilium/bgp/bgp.yaml`

**Added large community tags:**
```yaml
# LoadBalancer services - Public community
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: loadbalancer-services
spec:
  advertisements:
  - advertisementType: "Service"
    attributes:
      communities:
        large: ["4200001000:0:200"]  # CL_K8S_PUBLIC

# Pod CIDRs - Internal community
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: pod-cidr
spec:
  advertisements:
  - advertisementType: "PodCIDR"
    attributes:
      communities:
        large: ["4200001000:0:100"]  # CL_K8S_INTERNAL (NEW)
```

### Change 2: FRR Route-Maps

**File:** `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

**Added strict PodCIDR filtering with community matching:**
```
# Accept PodCIDR ONLY if it has the K8S_INTERNAL community
route-map RM_VMS_IN_V6 permit 5
 match ipv6 address prefix-list PL_K8S_PODS_V6
 match large-community CL_K8S_INTERNAL
exit
!
# Explicitly deny PodCIDR without the community (security)
route-map RM_VMS_IN_V6 deny 6
 match ipv6 address prefix-list PL_K8S_PODS_V6
exit
!
# (existing permit rules 10, 15, 20 follow)
# ...
route-map RM_VMS_IN_V6 deny 999
exit
```

**Added PodCIDR to global-to-vrf import:**
```
route-map RM_GLOBAL_TO_VRF_V6 permit 30
 match ipv6 address prefix-list PL_K8S_PODS_V6
 match large-community CL_K8S_INTERNAL
exit
```

**Added PodCIDR to outbound advertisements:**
```
route-map RM_VMS_OUT_V6 permit 30
 match ipv6 address prefix-list PL_K8S_PODS_V6
 match large-community CL_K8S_INTERNAL
exit
```

### Implementation Status

- ✅ Changes committed to repository
- ✅ Cilium manifests validated: `kubectl kustomize kubernetes/apps/networking/cilium/bgp`
- ⏳ Pending deployment to FRR (Ansible)
- ⏳ Pending Cilium reconciliation (Flux)
- ⏳ Pending verification of pod routing

## Validation Questions

1. **Is the fix complete and correct?**
   - Does requiring BOTH prefix-list AND community matching provide proper security?
   - Is the explicit deny (rule 6) necessary or redundant?
   - Are the sequence numbers (5, 6) appropriate (before other permits)?

2. **Route-map flow analysis:**
   - Rule 5: Permit PodCIDR with CL_K8S_INTERNAL ✅
   - Rule 6: Deny PodCIDR without CL_K8S_INTERNAL (security)
   - Rule 10: Permit PL_TENANT_V6 (includes fd00:101::/48)
   - Rule 15: Permit PL_TENANT_GUA_V6 (GUA addresses)
   - Rule 20: Permit PL_K8S_LOOPBACKS_V6
   - Rule 999: Deny all

   **Question:** Could a malicious route matching fd00:101:224::/60 without the community tag slip through rule 10 (PL_TENANT_V6 permits fd00:101::/48)?

3. **Missing bird2 → Cilium export fix:**
   - The current bird2 config still has `export none` to Cilium
   - After FRR accepts pod CIDRs and propagates via iBGP, bird2 will receive them from FRR
   - **Question:** Does bird2 also need to export these routes back to Cilium, or does Cilium not need them?
   - **Expected:** Each node's bird2 should export OTHER nodes' pod CIDRs back to Cilium for routing

4. **Global-to-VRF and VMS-OUT route-maps:**
   - Why is RM_GLOBAL_TO_VRF_V6 permit 30 needed? (PodCIDRs are in VRF already)
   - Why is RM_VMS_OUT_V6 permit 30 needed? (Outbound to Talos nodes)
   - **Question:** What is the purpose of these additional permit rules?

## Additional Context

**Working BGP Elements:**
- ✅ Cilium → bird2 peering established
- ✅ bird2 → FRR peering established (6/6 nodes)
- ✅ LoadBalancer VIP advertisement (separate flow, working)
- ✅ Kubernetes API VIP routing (working after previous false ECMP fix)
- ✅ Loopback advertisement and routing (working)

**Non-Working:**
- ❌ Pod CIDR advertisement to FRR (blocked by route-map)
- ❌ Pod-to-pod connectivity across nodes
- ❌ Cilium cluster health (1/6 reachable)

**Goal:**
Enable BGP-based inter-node pod routing where Cilium learns routes dynamically via BGP instead of using `autoDirectNodeRoutes: true`. This enables multi-cluster routing and flexible routing policies via FRR.

## Expected Route Flow After Deployment

**After FRR and Cilium changes are deployed:**

```
1. Cilium (solcp02) advertises fd00:101:224:1::/64 with community 4200001000:0:100 → bird2
2. bird2 accepts from Cilium (protocol "cilium", import all)
3. bird2 exports to FRR upstream (accepts all, passes through community tag)
4. FRR RM_VMS_IN_V6 permit 5: Accepts route (matches PL_K8S_PODS_V6 AND CL_K8S_INTERNAL)
5. FRR stores route in BGP table for vrf_evpnz1
6. FRR propagates via iBGP to pve02 and pve03
7. All 3 PVE nodes now have fd00:101:224:1::/64 in their BGP tables
8. Each PVE's FRR advertises OTHER nodes' pod CIDRs back to their connected Talos nodes
   - pve01 advertises fd00:101:224:1::/64 (from solcp02) to solcp01 via RM_VMS_OUT_V6 permit 30
9. solcp01's bird2 receives fd00:101:224:1::/64 from FRR (protocol "upstream", import all)
10. ❓ bird2 exports to Cilium? (Currently: export none - BLOCKS HERE?)
11. ❓ Cilium installs route for cross-node pod traffic?
```

**Critical question:** Does step 10 require changing bird2's `export none` to bidirectional?

## Deployment and Verification Plan

### Step 1: Deploy FRR Configuration
```bash
cd /Users/sulibot/repos/github/home-ops/ansible/lae.proxmox
ansible-playbook -i inventory/hosts.ini playbooks/stage2-configure-frr.yml
```

### Step 2: Reconcile Cilium BGP Manifests
```bash
# Via Flux (automatic)
flux reconcile kustomization cilium-bgp

# Or manual application
kubectl apply -k kubernetes/apps/networking/cilium/bgp/
```

### Step 3: Verify FRR Accepts Pod CIDRs
```bash
# Check FRR received pod CIDRs from Talos nodes
ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 unicast fd00:101:224::/60 longer-prefixes"'
# Expected: All 6 nodes' /64 subnets visible

# Check community tags
ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 unicast fd00:101:224::/64 json"' | jq '.paths[0].largeCommunity'
# Expected: ["4200001000:0:100"]
```

### Step 4: Verify FRR Advertises Pod CIDRs Back to Nodes
```bash
# Check what pve01 advertises to solcp01
ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 unicast neighbors fd00:101::11 advertised-routes" | grep "fd00:101:224"'
# Expected: Pod CIDRs from OTHER nodes (not solcp01's own)
```

### Step 5: Verify Kernel Routes on Talos Nodes
```bash
export TALOSCONFIG=/path/to/talosconfig
talosctl -n fd00:101::11 get routes | grep "fd00:101:224"
# Expected: Routes to ALL nodes' pod CIDRs (not just local)
```

### Step 6: Verify Cilium Cluster Health
```bash
kubectl exec -n kube-system ds/cilium -c cilium-agent -- \
  cilium-dbg status --verbose | grep "Cluster health"
# Expected: 6/6 reachable (instead of 1/6)
```

### Step 7: Test Pod-to-Pod Connectivity
```bash
# Get pod IPs on different nodes
kubectl get pods -A -o wide | grep -E "solcp02|solwk01"

# Exec into a pod on solcp01
kubectl exec -it <pod-on-solcp01> -- ping6 -c 3 <pod-ip-on-solcp02>
# Expected: Successful ping
```

## Request for Validation

Please validate:

1. **Root cause confirmation:** Is the analysis correct that FRR was blocking pod CIDRs?

2. **Implemented fix validation:**
   - Are the FRR route-map changes correct and complete?
   - Is the community-based filtering approach secure and appropriate?
   - Are sequence numbers and rule order correct?

3. **Missing piece identification:**
   - Does bird2 need to change `export none` to export routes from "upstream" back to Cilium?
   - If yes, provide the exact bird2 configuration change needed
   - If no, explain how Cilium will learn the routes

4. **Complete configuration:**
   - Are there any other changes needed beyond FRR route-maps and Cilium advertisements?
   - Will the expected route flow work as described?

5. **Verification plan:**
   - Are the verification steps comprehensive?
   - Any additional checks or commands needed?

6. **Edge cases and security:**
   - Could malicious routes bypass the filters?
   - What happens if a node advertises pod CIDRs without the community tag?
   - Is the explicit deny (rule 6) necessary?

Thank you for validating this complex BGP routing fix!
