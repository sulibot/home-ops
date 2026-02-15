# CoreDNS Cannot Reach Kubernetes API ClusterIP - Cilium BGP Routing Issue

## Problem Statement

CoreDNS pods in a Talos Kubernetes cluster cannot connect to the Kubernetes API ClusterIP service, causing continuous timeout errors and preventing the cluster from becoming fully operational. This issue occurs when using Cilium with BGP-based routing (`autoDirectNodeRoutes: false`).

## Error Messages

```
[ERROR] plugin/kubernetes: Failed to watch: failed to list *v1.Service: Get "https://[fd00:101:96::1]:443/api/v1/services?limit=500&resourceVersion=0": dial tcp [fd00:101:96::1]:443: i/o timeout
[INFO] plugin/ready: Plugins not ready: "kubernetes"
```

CoreDNS pods remain in Running state but never become Ready (0/1).

## Environment

- **Kubernetes**: v1.34.1 on Talos v1.12.1
- **CNI**: Cilium v1.18.6
- **Platform**: Proxmox VE 8.3 with 6 nodes (3 control plane, 3 workers)
- **Routing**: BGP-based using bird2 + FRR
- **Network**: Dual-stack (IPv4 + IPv6), IPv6-first

## Network Configuration

**IP Addressing:**
- Node IPs: `fd00:101::11-13` (control plane), `fd00:101::21-23` (workers)
- Pod CIDR: `fd00:101:224::/60` (per-node /80 subnets)
- Service CIDR: `fd00:101:96::/108`
- **Kubernetes API ClusterIP**: `fd00:101:96::1` ← Cannot be reached from pods

**BGP Architecture:**
```
Cilium (ASN 4220101000)
    ↓ localhost peering (::1)
bird2 (ASN 42101010XX per node)
    ↓ BGP over fd00:101::/64
FRR on PVE nodes (ASN 4200001000)
```

## Current Cilium Configuration

File: `kubernetes/apps/networking/cilium/app/values.yaml`

```yaml
# kube-proxy replacement enabled
kubeProxyReplacement: true

# Socket LB - HOST NAMESPACE ONLY
socketLB:
  enabled: true
  hostNamespaceOnly: true  # ← Pods cannot use socket LB!

# BGP routing configuration
routingMode: native
autoDirectNodeRoutes: false  # ← Use BGP-learned routes
directRoutingSkipUnreachable: false  # ← Must be false when autoDirectNodeRoutes is false

# Masquerading
enableIPv4Masquerade: false
enableIPv6Masquerade: true
bpf:
  masquerade: true  # ← Enabled but doesn't fix the issue
  lbMode: snat
  lbExternalClusterIP: true
  hostLegacyRouting: true

# BGP Control Plane
bgpControlPlane:
  enabled: true
```

## Key Configuration Constraints

### 1. Compatibility Requirement
When `autoDirectNodeRoutes: false`, setting `directRoutingSkipUnreachable: true` causes Cilium to fail with:
```
Flag direct-routing-skip-unreachable cannot be enabled when auto-direct-node-routes is not enabled.
```

Therefore, we **must** use `directRoutingSkipUnreachable: false`.

### 2. Socket LB Limitation
`socketLB.hostNamespaceOnly: true` was set to fix libp2p/Spegel compatibility issues. However, this restricts socket-based load balancing to the host namespace only.

**Cilium status shows:**
```
Socket LB:            Enabled
Socket LB Coverage:   Hostns-only  ← Critical limitation
```

This means pods cannot use socket LB to reach ClusterIP services.

### 3. BPF Masquerading
Enabled `bpf.masquerade: true` but CoreDNS still cannot reach ClusterIP (same timeout errors persist).

## Working vs Broken Configuration

### Previously Working (Before BGP)
```yaml
autoDirectNodeRoutes: true  # Cilium manages routes
directRoutingSkipUnreachable: true
socketLB.hostNamespaceOnly: true
bpf.masquerade: false
```
✅ ClusterIP services worked
❌ Cannot use BGP for dynamic routing

### Current (BGP-enabled, Broken)
```yaml
autoDirectNodeRoutes: false  # Use BGP routes
directRoutingSkipUnreachable: false  # Required for compatibility
socketLB.hostNamespaceOnly: true
bpf.masquerade: true  # Tried enabling, doesn't help
```
✅ BGP routing works (LoadBalancer VIPs advertised correctly)
❌ ClusterIP services unreachable from pods

## Verification Commands & Results

### CoreDNS Status
```bash
$ kubectl get pods -n kube-system -l k8s-app=kube-dns
NAME                       READY   STATUS    RESTARTS   AGE
coredns-76899f5fd7-gmc2r   0/1     Running   0          23m
coredns-76899f5fd7-qq7zh   0/1     Running   0          23m
```

### Kubernetes Service
```bash
$ kubectl get svc kubernetes
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   fd00:101:96::1   <none>        443/TCP   25m
```
The service exists and kube-apiserver pods are running.

### Cilium Config
```bash
$ kubectl get cm -n kube-system cilium-config -o yaml | grep -E "(auto-direct|direct-routing|bpf-masquerade|socket)"
  auto-direct-node-routes: "false"
  direct-routing-skip-unreachable: "false"
  enable-bpf-masquerade: "true"
  bpf-lb-sock: "true"
  bpf-lb-sock-hostns-only: "true"
```

### Cilium Status
```bash
$ kubectl exec -n kube-system ds/cilium -- cilium-dbg status | grep -A 3 "KubeProxyReplacement"
KubeProxyReplacement:   True
  Status:               True
  Socket LB:            Enabled
  Socket LB Coverage:   Hostns-only
```

## Questions

### Primary Question
**How can I configure Cilium to support BOTH:**
1. BGP-based inter-node routing (`autoDirectNodeRoutes: false`)
2. ClusterIP services accessible from pod namespaces

### Specific Questions

1. **Is `autoDirectNodeRoutes: false` compatible with ClusterIP services?**
   - Does ClusterIP routing require auto-direct-node-routes to be enabled?
   - Or can it work with externally-learned (BGP) routes?

2. **Socket LB vs BPF Datapath:**
   - With `hostNamespaceOnly: true`, how should pods reach ClusterIP services?
   - Is BPF masquerading the correct mechanism?
   - Or do I need to enable socket LB for all namespaces?

3. **If I set `socketLB.hostNamespaceOnly: false`:**
   - Will this break libp2p/Spegel compatibility?
   - Is there a way to selectively enable it for certain pods?

4. **Alternative configurations:**
   - Can Cilium use hybrid routing (BGP for pod traffic, auto-direct for ClusterIP)?
   - Is there a Cilium v1.18.x example config for BGP routing + working ClusterIP?

## What I've Tried

1. ✅ **Enabled BPF masquerading** (`bpf.masquerade: true`)
   - Result: No change, still timeout

2. ✅ **Verified BGP routing** (separate from this issue)
   - BGP architecture working correctly
   - LoadBalancer VIP advertisement functional
   - bird2 ↔ FRR peering established

3. ❌ **Cannot test with `autoDirectNodeRoutes: true`**
   - Would break BGP routing (defeats the purpose)

4. ❌ **Cannot set `directRoutingSkipUnreachable: true`**
   - Causes compatibility error with `autoDirectNodeRoutes: false`

## Expected Outcome

A Cilium configuration that enables:
- ✅ BGP-based inter-node pod routing
- ✅ ClusterIP services reachable from all pods (including CoreDNS)
- ✅ Compatible with Talos Kubernetes
- ✅ No breaking changes to existing BGP architecture

## Additional Context

### Why BGP Routing?
We use BGP to:
- Dynamically advertise LoadBalancer VIPs to the network
- Enable flexible routing policies via FRRouting
- Support multi-cluster routing in the future

### Why Socket LB hostNamespaceOnly?
Original comment from values.yaml:
```yaml
# Setting hostNamespaceOnly: true fixes libp2p compatibility (Spegel) and connection tracking races
# Pod traffic uses standard TC-BPF datapath (robust, fully compatible)
```

### Current Impact
- Cluster is operational (nodes Ready, control plane healthy)
- CoreDNS not ready (blocks DNS resolution)
- Cannot proceed with Flux GitOps deployment (depends on CoreDNS)
- LoadBalancer services work (tested, VIP reachable from external networks)

## Request

Please provide:
1. The correct Cilium configuration for BGP routing + working ClusterIP
2. Explanation of how ClusterIP traffic should be routed with `autoDirectNodeRoutes: false`
3. Any Cilium documentation or examples showing this configuration
4. Step-by-step fix if configuration changes are needed

Thank you for your help!
