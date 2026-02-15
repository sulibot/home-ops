# CoreDNS ClusterIP Timeout Issue with Cilium BGP Routing Configuration

## Goal

Enable CoreDNS pods to successfully connect to the Kubernetes API ClusterIP service (`fd00:101:96::1:443`) while maintaining BGP-based routing for inter-node pod communication in a Talos Kubernetes cluster.

## Current Issue

CoreDNS pods cannot reach the Kubernetes API ClusterIP service, causing continuous timeout errors and preventing CoreDNS from becoming ready.

### Symptoms

```
[ERROR] plugin/kubernetes: Failed to watch: failed to list *v1.Service: Get "https://[fd00:101:96::1]:443/api/v1/services?limit=500&resourceVersion=0": dial tcp [fd00:101:96::1]:443: i/o timeout
[INFO] plugin/ready: Plugins not ready: "kubernetes"
```

### Pod Status
```bash
$ kubectl get pods -n kube-system -l k8s-app=kube-dns
NAME                       READY   STATUS    RESTARTS   AGE
coredns-76899f5fd7-6wrtg   0/1     Running   0          10m
coredns-76899f5fd7-tqml7   0/1     Running   0          10m
```

**Readiness probe failing:** `HTTP probe failed with statuscode: 503`

## Architecture Context

### Cluster Configuration

**Platform:** Talos Kubernetes v1.34.1
**CNI:** Cilium v1.18.6
**Routing:** BGP-based with FRRouting (bird2 on Talos nodes)

### Network Topology

```
┌─────────────────────────────────────────────────────┐
│ Cilium BGP (each Talos node)                       │
│ ASN: 4220101000 (cluster-wide)                     │
│ Advertises: LoadBalancer VIPs, pod CIDRs           │
└───────────────┬─────────────────────────────────────┘
                │ Localhost peering (::1:179)
                │
┌───────────────┴─────────────────────────────────────┐
│ Bird2 (each Talos node) - ExtensionServiceConfig   │
│ ASN: 42101010XX (per-node unique)                   │
│ Peers:                                              │
│  1. Cilium (passive, ::1) ✅ ESTABLISHED           │
│  2. PVE VRF (fd00:101::fffe) ✅ ESTABLISHED         │
│ Advertises: Loopbacks + VIPs from Cilium           │
└───────────────┬─────────────────────────────────────┘
                │ BGP over fd00:101::/64
                │
┌───────────────┴─────────────────────────────────────┐
│ PVE FRR - VRF vrf_evpnz1                            │
│ ASN: 4200001000                                     │
│ Learns routes from all 6 Talos nodes               │
└─────────────────────────────────────────────────────┘
```

**IP Ranges:**
- Node IPs: `fd00:101::11-13` (control plane), `fd00:101::21-23` (workers)
- Pod CIDR: `fd00:101:224::/60` (subdivided into /80 per node)
- Service CIDR: `fd00:101:96::/108`
- Kubernetes API ClusterIP: `fd00:101:96::1`

### BGP Routing Configuration

**Goal:** Use BGP to learn inter-node routes instead of Cilium's auto-direct-node-routes.

**Cilium Configuration (kubernetes/apps/networking/cilium/app/values.yaml):**
```yaml
# Lines 44-53
routingMode: native
autoDirectNodeRoutes: false  # Use BGP-learned routes for inter-node traffic
directRoutingSkipUnreachable: false  # Install routes to all nodes
endpointRoutes:
  enabled: false  # Install per-node CIDR routes, not per-pod

# Lines 18-20 - Socket LB Configuration
socketLB:
  enabled: true
  hostNamespaceOnly: true  # Restrict to host namespace (fixes libp2p/Spegel issues)

# Lines 65-77 - BPF Configuration
bpf:
  masquerade: false  # BPF masquerading disabled
  lbMode: snat
  lbExternalClusterIP: true
  hostLegacyRouting: true

# Lines 23-32 - Masquerading
enableIPv4Masquerade: false
enableIPv6Masquerade: true  # Masquerade ULA pod traffic to GUA internet

# Line 13 - kube-proxy replacement
kubeProxyReplacement: true
```

## The Conflict

### Configuration Incompatibility Discovered

When setting `autoDirectNodeRoutes: false` (required for BGP routing), the setting `directRoutingSkipUnreachable` **MUST be false** to avoid Cilium startup errors:

```
Flag direct-routing-skip-unreachable cannot be enabled when auto-direct-node-routes is not enabled.
```

**However**, with the current configuration:
- `autoDirectNodeRoutes: false` ✅ (for BGP routing)
- `directRoutingSkipUnreachable: false` ✅ (to avoid compatibility error)
- `socketLB.hostNamespaceOnly: true` ✅ (fixes libp2p/Spegel compatibility)
- `bpf.masquerade: false` ✅ (current setting)

**Result:** CoreDNS pods (and potentially other pods) **cannot reach ClusterIP services**.

## Evidence

### 1. Cilium Configuration Status

```bash
$ kubectl get cm -n kube-system cilium-config -o yaml | grep -E "(direct-routing|auto-direct|bpf-masquerade|socket)"
  auto-direct-node-routes: "false"
  direct-routing-skip-unreachable: "false"
  enable-bpf-masquerade: "false"
  bpf-lb-sock: "true"
  bpf-lb-sock-hostns-only: "true"
  kube-proxy-replacement: "true"
```

### 2. Cilium KubeProxyReplacement Status

```bash
$ kubectl exec -n kube-system ds/cilium -- cilium-dbg status --verbose | grep -A 5 "KubeProxyReplacement"
KubeProxyReplacement:   True
  Status:               True
  Socket LB:            Enabled
  Socket LB Tracing:    Enabled
  Socket LB Coverage:   Hostns-only  ← CRITICAL: Only host namespace!
```

### 3. CoreDNS Error Pattern

All errors show the same pattern:
- Attempting to connect to Kubernetes API ClusterIP: `fd00:101:96::1:443`
- Connection timeout (not connection refused)
- Suggests routing issue, not service availability issue

### 4. Kubernetes API Service

```bash
$ kubectl get svc kubernetes
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   fd00:101:96::1   <none>        443/TCP   15m
```

The service exists and kube-apiserver pods are running on control plane nodes.

### 5. Working Configuration (Before BGP Changes)

Previously, the cluster worked with:
```yaml
autoDirectNodeRoutes: true  # Cilium managed node routes
directRoutingSkipUnreachable: true  # Skip unreachable nodes
```

This configuration worked because Cilium handled all routing directly. However, this prevents using BGP for dynamic routing.

## Questions for Gemini

### 1. ClusterIP Routing with BGP-based Inter-Node Routing

**How can Cilium correctly route ClusterIP traffic when:**
- `autoDirectNodeRoutes: false` (using BGP-learned routes for inter-node traffic)
- `directRoutingSkipUnreachable: false` (required for compatibility)
- `socketLB.hostNamespaceOnly: true` (required for libp2p/Spegel compatibility)

Does ClusterIP routing require `autoDirectNodeRoutes: true`, or can it work with BGP-based routing?

### 2. Socket LB vs BPF Masquerading

**What is the correct way to enable ClusterIP access from pod namespaces?**

Option A: Enable socket LB for all namespaces:
```yaml
socketLB:
  enabled: true
  hostNamespaceOnly: false  # Allow pods to use socket LB
```
**Risk:** May break libp2p/Spegel compatibility (original reason for hostNamespaceOnly)

Option B: Enable BPF masquerading:
```yaml
bpf:
  masquerade: true  # Enable BPF masquerading for ClusterIP
```
**Question:** Is BPF masquerading the correct mechanism for ClusterIP access with kube-proxy replacement?

Option C: Something else entirely?

### 3. BGP Routing + ClusterIP Compatibility

**Is there a known-good configuration for:**
- BGP-based inter-node pod routing (`autoDirectNodeRoutes: false`)
- Working ClusterIP services for pods
- Compatible with Cilium v1.18.6

**Example configuration or documentation link would be extremely helpful.**

### 4. Alternative: Hybrid Routing?

**Can Cilium use:**
- BGP-learned routes for inter-node pod traffic (data plane)
- Auto-direct-node-routes for ClusterIP services (control plane)

Or are these mutually exclusive?

## Configuration Files

### Main Cilium Values (kubernetes/apps/networking/cilium/app/values.yaml)

```yaml
---
# Cilium Bootstrap Values for cluster-101
# Talos-specific configuration with dual-stack networking

# API Server endpoint - use localhost for Talos
k8sServiceHost: localhost
k8sServicePort: 7445

# Replace kube-proxy with Cilium
kubeProxyReplacement: true

# Socket-based load balancing - host namespace only
# Setting hostNamespaceOnly: true fixes libp2p compatibility (Spegel) and connection tracking races
# Pod traffic uses standard TC-BPF datapath (robust, fully compatible)
socketLB:
  enabled: true              # Enable socket-level load balancing
  hostNamespaceOnly: true    # Restrict to host namespace (fixes networking issues)

# Enable dual-stack with IPv6 first
ipv4:
  enabled: true
ipv6:
  enabled: true

# Masquerade control - IPv6 masquerading required for ClusterIP services
# While pod-to-pod uses native routing (no masquerade), ClusterIPs are virtual
# and need masquerading for kube-proxy replacement to function with BPF
enableIPv4Masquerade: false  # Keep false - will remove IPv4 eventually
enableIPv6Masquerade: true   # Enabled: Masquerade ULA Pod traffic to GUA Internet

# IPAM mode - kubernetes with per-node /80 IPv6 allocations (standard)
ipam:
  mode: kubernetes

# IPv6 configuration - require pod CIDR from node spec
k8s:
  requireIPv6PodCIDR: true

# Native routing (no encapsulation for better performance)
routingMode: native
# Disable autoDirectNodeRoutes so inter-node pod routing follows BGP-learned routes
autoDirectNodeRoutes: false
directRoutingSkipUnreachable: false  # Install routes to all nodes
# Disable endpointRoutes so Cilium installs per-node CIDR (/24) routes instead of per-endpoint (/32) routes
endpointRoutes:
  enabled: false

# Explicitly set MTU to match the underlying VXLAN network (1450)
mtu: 1450

# Native routing CIDRs - ULA for intra-cluster native routing
ipv4NativeRoutingCIDR: 10.101.0.0/16
ipv6NativeRoutingCIDR: fd00:101::/48

# BPF configuration optimized for Talos + Istio Ambient
bpf:
  # Enable BPF masquerading
  masquerade: false
  # LB mode: SNAT by default, allow per-service DSR/hybrid via annotations
  lbMode: snat
  lbModeAnnotation: true
  # Enable external ClusterIP access to handle LoadBalancer IPs
  lbExternalClusterIP: true
  # Map tuning for performance
  mapDynamicSizeRatio: 0.005
  preallocateMaps: true
  # Use legacy routing for host-bound traffic (required for stability/compatibility)
  hostLegacyRouting: true

# BGP Control Plane enabled; Cilium only peers to local FRR for LB VIP origination
bgpControlPlane:
  enabled: true
```

## System Information

- **Cilium Version**: v1.18.6
- **Kubernetes Version**: v1.34.1
- **Talos Version**: v1.12.1
- **Platform**: Proxmox VE 8.3
- **Node Count**: 6 (3 control plane, 3 workers)
- **Deployment Method**: Talos inline manifests (bootstrap) → Flux (management)

## Expected Outcome

A configuration that allows:
1. ✅ BGP-based inter-node pod routing (for dynamic route learning)
2. ✅ ClusterIP services accessible from all pods (including CoreDNS)
3. ✅ Compatible with `autoDirectNodeRoutes: false` + `directRoutingSkipUnreachable: false`
4. ✅ No conflicts with libp2p/Spegel (hostNamespaceOnly socket LB if needed)

## Additional Context

This issue arose after successfully implementing BGP-based VIP advertisement for LoadBalancer services. The BGP architecture (Cilium → bird2 → FRR) is working correctly for:
- LoadBalancer VIP advertisement ✅
- Pod CIDR advertisement ✅
- Inter-node routing (not yet fully tested due to CoreDNS issue)

The CoreDNS ClusterIP timeout is the blocker preventing cluster from becoming fully operational.
