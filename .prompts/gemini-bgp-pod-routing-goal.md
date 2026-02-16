# BGP-Based Pod Routing with Cilium - Implementation Failure Analysis

## Primary Goal

Implement **BGP-based inter-node pod routing** in a Talos Kubernetes cluster where:
1. Cilium advertises pod CIDRs to a local bird2 BGP daemon
2. bird2 advertises pod CIDRs to FRRouting (FRR) on Proxmox nodes
3. FRR propagates routes via iBGP to all Proxmox nodes
4. Nodes learn pod routes from FRR via BGP instead of Cilium auto-installing them
5. This enables dynamic routing, multi-cluster support, and flexible routing policies

## Current Status: FAILED

**What works:**
- ✅ LoadBalancer VIP advertisement (Cilium → bird2 → FRR → network)
- ✅ Kubernetes API VIP routing (fixed false ECMP issue)
- ✅ BGP peering established (Cilium ↔ bird2 ↔ FRR)
- ✅ Cilium advertising pod CIDRs to bird2

**What doesn't work:**
- ❌ Pod-to-pod connectivity with `autoDirectNodeRoutes: false`
- ❌ BGP-learned routes not being installed by Cilium
- ❌ Forced to use `autoDirectNodeRoutes: true` as workaround

## Architecture

### Network Topology

```
┌─────────────────────────────────────────┐
│ Kubernetes Cluster (cluster-101)       │
│ 6 nodes: 3 control plane, 3 workers    │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────────────────────────┐  │
│  │ Cilium CNI (each node)           │  │
│  │ ASN: 4220101000 (cluster-wide)   │  │
│  │ Router ID: 10.101.254.XX         │  │
│  │ Advertises:                      │  │
│  │  - Pod CIDR: fd00:101:224:X::/64 │  │
│  │  - LoadBalancer VIPs             │  │
│  └────────┬─────────────────────────┘  │
│           │ MP-BGP over ::1:179         │
│  ┌────────▼─────────────────────────┐  │
│  │ bird2 v2.17.1 (ExtensionService) │  │
│  │ ASN: 42101010XX (per-node)       │  │
│  │ Router ID: 10.101.254.XX         │  │
│  │ Peers:                           │  │
│  │  1. Cilium (::1) - ESTABLISHED   │  │
│  │  2. PVE FRR (fd00:101::fffe)     │  │
│  │        - ESTABLISHED              │  │
│  └────────┬─────────────────────────┘  │
│           │ BGP over fd00:101::/64      │
└───────────┼─────────────────────────────┘
            │
┌───────────▼─────────────────────────────┐
│ Proxmox VE FRR (3 nodes)                │
│ ASN: 4200001000                         │
│ VRF: vrf_evpnz1 (Talos isolation)       │
│ iBGP: Full mesh between pve01-03        │
│ eBGP: Peers with edge router            │
└─────────────────────────────────────────┘
```

### IP Addressing

- **Node IPs**: `fd00:101::11-13` (control), `fd00:101::21-23` (workers)
- **Pod CIDRs**: `fd00:101:224::/60` (subdivided into /64 per node)
  - solcp01: `fd00:101:224::/64`
  - solcp02: `fd00:101:224:1::/64`
  - solwk01: `fd00:101:224:2::/64`
  - solwk02: `fd00:101:224:3::/64`
  - solwk03: `fd00:101:224:4::/64`
  - solcp03: `fd00:101:224:5::/64`
- **Service CIDR**: `fd00:101:96::/108`
- **Loopbacks**: `fd00:101:fe::/64`

## Configuration Attempts

### Attempt 1: Disable autoDirectNodeRoutes (FAILED)

**Cilium Configuration:**
```yaml
# kubernetes/apps/networking/cilium/app/values.yaml
routingMode: native
autoDirectNodeRoutes: false  # Let BGP provide routes
directRoutingSkipUnreachable: false  # Required when autoDirectNodeRoutes is false
endpointRoutes:
  enabled: false  # Use per-node CIDR routes

bgpControlPlane:
  enabled: true
```

**Result:**
- ❌ Cilium cluster health: 1/6 nodes reachable
- ❌ Pods cannot communicate across nodes
- ❌ cert-manager, external-secrets, and other apps crash
- ❌ Error: `dial tcp [fd00:101:224:3::40bd]:9403: connect: connection refused`

**Root Cause:**
With `autoDirectNodeRoutes: false`, Cilium does **not** install kernel routes to other nodes' pod CIDRs. It expects routes to be provided externally (via BGP), but they are not being installed.

### Attempt 2: Emergency Workaround (CURRENT)

**Configuration:**
```yaml
autoDirectNodeRoutes: true  # ← Reverted to default
directRoutingSkipUnreachable: false  # Keep for compatibility
bpf.masquerade: true  # Enabled for ClusterIP access
```

**Result:**
- ✅ Cluster fully operational
- ✅ All pods healthy
- ❌ **Goal NOT achieved** - using Cilium auto-direct routes, not BGP

## Evidence & Analysis

### 1. Cilium BGP Configuration

**Peer Configuration (cilium-bgp-config.yaml):**
```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: frr-local-mpbgp
spec:
  families:
  - afi: ipv6
    safi: unicast
    advertisements:
      matchLabels:
        advertise: "bgp"
```

**Pod CIDR Advertisement:**
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
        large: ["4200001000:0:100"]  # Internal
```

### 2. Cilium IS Advertising Pod CIDRs

```bash
$ kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp routes advertised ipv6 unicast
VRouter      Peer   Prefix              NextHop   Age      Attrs
4220101000   ::1    fd00:101:224::/64   ::1       14m23s   [{Origin: i} ...]
```

✅ Cilium successfully advertises local pod CIDR to bird2.

### 3. BGP Session Status

```bash
$ kubectl get ciliumbgpnodeconfig -o yaml | grep -A 10 status
status:
  bgpInstances:
  - localASN: 4220101000
    name: local-bird2
    peers:
    - establishedTime: "2026-02-15T13:41:09Z"  # ✅ Established
      name: bird2-local
      peerASN: 4210101011
```

✅ BGP session between Cilium and bird2 is established and healthy.

### 4. Routing Table Analysis (autoDirectNodeRoutes: false)

**On Node (solcp01):**
```bash
$ talosctl -n fd00:101::11 get routes | grep "224:"
fd00:101:224::/64       cilium_host       1024    # ✅ Local pod CIDR only
```

**Missing routes to other nodes' pod CIDRs:**
- ❌ No route to `fd00:101:224:1::/64` (solcp02)
- ❌ No route to `fd00:101:224:2::/64` (solwk01)
- ❌ No route to `fd00:101:224:3::/64` (solwk02)
- ❌ No route to `fd00:101:224:4::/64` (solwk03)
- ❌ No route to `fd00:101:224:5::/64` (solcp03)

**Expected:** Routes to other nodes' pod CIDRs installed via BGP from bird2/FRR.

### 5. Cilium Configuration Matrix

| Setting | autoDirectNodeRoutes: true | autoDirectNodeRoutes: false |
|---------|----------------------------|------------------------------|
| **Route Source** | Cilium installs routes | External (BGP) provides routes |
| **Pod Connectivity** | ✅ Works | ❌ Broken |
| **BGP Requirement** | Optional | **Required** |
| **Current Status** | ✅ Using this | ❌ Target config |

## Key Questions for Gemini

### 1. Route Installation Mechanism

**With `autoDirectNodeRoutes: false`, how should routes be installed?**

Does Cilium:
- A) Expect routes to exist in kernel table and use them passively?
- B) Import routes from a BGP daemon running on the same node?
- C) Require a specific mechanism to learn routes?
- D) Not support this mode at all for pod routing?

### 2. Bird2 Integration

**Is bird2 actually learning pod CIDRs from Cilium and redistributing them?**

We confirmed Cilium advertises to bird2, but:
- Is bird2 receiving and accepting these routes?
- Is bird2 advertising to FRR (fd00:101::fffe)?
- Is FRR learning them and redistributing via iBGP?
- Are routes coming back to the nodes from FRR?

**How to verify the BGP route flow:**
```
Cilium (pod CIDR) → bird2 → FRR → iBGP mesh → FRR (all nodes) → bird2 → kernel?
```

### 3. Route Import Configuration

**Does Cilium need additional configuration to import BGP routes?**

Possible missing configuration:
```yaml
# Is something like this needed?
bgpControlPlane:
  enabled: true
  importRoutes: true  # ???
  installRoutes: true  # ???
```

### 4. Native Routing + BGP

**Is `routingMode: native` + `autoDirectNodeRoutes: false` + BGP a supported configuration?**

Documentation references:
- Does Cilium v1.18.6 support importing routes from external BGP daemons?
- Are there examples of this working with bird2 or FRR?
- Is there alternative configuration needed?

### 5. Kernel Route Installation

**Who installs the BGP-learned routes in the kernel?**

Options:
- A) bird2 installs them → Cilium uses them passively
- B) FRR installs them → Cilium uses them
- C) Cilium imports from bird2 BGP and installs them
- D) This workflow is not supported

### 6. Alternative: Route Reflector Mode?

**Should we use Cilium as a BGP route reflector instead?**

Instead of:
```
Cilium → bird2 → FRR → network
```

Use:
```
Cilium (all nodes) → FRR directly?
```

But this loses the ability to tag/filter routes with bird2.

## What We Need

### Desired Configuration

```yaml
# Cilium values.yaml
routingMode: native
autoDirectNodeRoutes: false  # Use BGP routes
bgpControlPlane:
  enabled: true
  # ??? What else is needed to import routes from bird2?

# Some mechanism for Cilium to:
# 1. Advertise local pod CIDR to bird2 ✅ (working)
# 2. Import other nodes' pod CIDRs from bird2 ❌ (not working)
# 3. Install imported routes in kernel ❌ (not working)
```

### Expected Behavior

1. Each node's Cilium advertises its pod CIDR to bird2
2. bird2 advertises to FRR with community tags
3. FRR propagates to all nodes via iBGP
4. Each node's bird2 receives all other nodes' pod CIDRs
5. **Routes are installed in kernel** (this step is failing)
6. Cilium uses kernel routes for inter-node pod traffic

### Verification Commands

```bash
# Check Cilium advertisements (working)
kubectl exec -n kube-system ds/cilium -- cilium-dbg bgp routes advertised ipv6 unicast

# Check kernel routes (missing remote pod CIDRs)
ip -6 route show | grep fd00:101:224:

# Check BGP session (established)
kubectl get ciliumbgpnodeconfig -o yaml

# Check bird2 routes (need to verify)
# How to query bird2 running in ExtensionService?

# Check FRR routes (need to verify)
ssh root@10.10.0.1 'vtysh -c "show bgp vrf vrf_evpnz1 ipv6 unicast"'
```

## Constraints & Requirements

### Must Maintain

1. ✅ LoadBalancer VIP advertisement via BGP (working, must not break)
2. ✅ Kubernetes API VIP routing (working, must not break)
3. ✅ ClusterIP service access from pods (working with bpf.masquerade: true)
4. ✅ iBGP full mesh between Proxmox nodes (working)
5. ✅ BGP community tagging for route filtering (working)

### Architecture Constraints

- **Cannot modify:** Proxmox FRR configuration (production network)
- **Can modify:** Cilium configuration, bird2 configuration, Talos settings
- **Must use:** bird2 as intermediate BGP daemon (for route tagging/filtering)
- **Must support:** Dual-stack (IPv4 + IPv6), IPv6-first

### Compatibility Requirements

- Talos v1.12.1 (immutable OS, limited customization)
- Cilium v1.18.6 (kube-proxy replacement enabled)
- bird2 v2.17.1 (running as ExtensionService)
- FRRouting 10.5.1 (on Proxmox VE)

## Configuration Files

### Current Cilium Values (Workaround)

```yaml
# kubernetes/apps/networking/cilium/app/values.yaml
routingMode: native
autoDirectNodeRoutes: true  # ← WORKAROUND (want: false)
directRoutingSkipUnreachable: false
endpointRoutes:
  enabled: false

kubeProxyReplacement: true
socketLB:
  enabled: true
  hostNamespaceOnly: true

enableIPv6Masquerade: true
bpf:
  masquerade: true
  lbMode: snat
  hostLegacyRouting: true

bgpControlPlane:
  enabled: true
```

### Bird2 Configuration (ExtensionService)

```bird
# Deployed via Talos ExtensionServiceConfig
router id 10.101.254.11;

protocol device {
  scan time 10;
}

protocol direct direct_routes {
  interface "dummy0", "lo", "ens18";
  ipv4 { import all; };
  ipv6 { import all; };
}

protocol bgp bgp_cilium {
  description "Cilium BGP (passive)";
  local ::1 as 4210101011;
  neighbor ::1 port 1790 as 4220101000;
  passive on;

  ipv4 {
    import filter {
      if source ~ [RTS_DEVICE, RTS_BGP] then accept;
      reject;
    };
    export filter {
      if proto = "direct_routes" then {
        bgp_large_community.add((4200001000, 0, 200));
        accept;
      }
      if source = RTS_BGP then accept;
      reject;
    };
  };

  ipv6 {
    import filter {
      if source ~ [RTS_DEVICE, RTS_BGP] then accept;
      reject;
    };
    export filter {
      if proto = "direct_routes" then {
        bgp_large_community.add((4200001000, 0, 200));
        accept;
      }
      if source = RTS_BGP then accept;
      reject;
    };
  };
}

protocol bgp bgp_upstream {
  description "PVE FRR (VRF)";
  local fd00:101::11 as 4210101011;
  neighbor fd00:101::fffe as 4200001000;
  multihop 2;

  ipv4 {
    import all;
    export filter {
      if source = RTS_BGP then accept;
      if proto = "direct_routes" then accept;
      reject;
    };
  };

  ipv6 {
    import all;
    export filter {
      if source = RTS_BGP then accept;
      if proto = "direct_routes" then accept;
      reject;
    };
  };
}
```

**Question:** Does bird2 need to install imported routes in the kernel? Currently using `import all` but routes may not be installed.

## Request for Gemini

Please provide:

1. **Root Cause Analysis:** Why routes are not being installed with `autoDirectNodeRoutes: false`
2. **Missing Configuration:** What Cilium/bird2/kernel settings are needed to make this work
3. **Route Flow Verification:** How to verify BGP routes flow: Cilium → bird2 → FRR → bird2 → kernel
4. **Working Example:** A known-good configuration for Cilium + external BGP daemon for pod routing
5. **Alternative Approaches:** If the current approach is not viable, what alternatives exist?
6. **Step-by-Step Fix:** Concrete configuration changes to achieve BGP-based pod routing

## Additional Information

- **Similar Working Setup:** LoadBalancer VIP advertisement works perfectly using the same BGP path
- **Cilium Docs:** The official docs don't clearly explain `autoDirectNodeRoutes: false` with external BGP
- **Community Examples:** Hard to find examples of Cilium + bird2 + external routing for pod CIDRs

Thank you for helping solve this critical routing architecture challenge!
