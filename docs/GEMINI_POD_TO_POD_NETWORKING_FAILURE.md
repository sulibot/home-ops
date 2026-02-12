# Gemini: Complete Pod-to-Pod Networking Failure in Cilium

## Problem Statement

**CRITICAL**: Complete pod-to-pod networking failure in a Talos Kubernetes cluster running Cilium 1.18.x in direct routing mode with dual-stack (IPv6 ULA + IPv4). Even basic ICMP ping between pods fails with 100% packet loss.

**Key Context**: This networking failure occurred in BOTH hybrid mode (`hostLegacyRouting: true`) AND direct mode (`hostLegacyRouting: false`), indicating the root cause is not the routing mode itself but a common configuration setting.

## Evidence of Complete Networking Failure

### 1. Pod-to-Pod ICMP Ping Fails (100% Packet Loss)

```bash
# Test ping from kustomize-controller to source-controller (same namespace)
$ kubectl exec -n flux-system deploy/kustomize-controller -- ping6 -c 3 fd00:101:224:2::aa96

PING fd00:101:224:2::aa96 (fd00:101:224:2::aa96): 56 data bytes
--- fd00:101:224:2::aa96 ping statistics ---
3 packets transmitted, 0 packets received, 100% packet loss
```

### 2. Pod-to-Pod HTTP Fails (Connection Timeout)

```bash
# Test HTTP from kustomize-controller to source-controller pod IP
$ kubectl exec -n flux-system deploy/kustomize-controller -- wget -O- --timeout=5 http://fd00:101:224:2::aa96:80

Connecting to fd00:101:224:2::aa96:80 ([fd00:101:224:2::aa96:80]:80)
wget: download timed out
```

### 3. ClusterIP Service Connectivity Fails

```bash
# Flux kustomize-controller trying to reach source-controller ClusterIP
failed to download archive: GET http://source-controller.flux-system.svc.cluster.local./gitrepository/...
giving up after 10 attempt(s): dial tcp [fd00:101:96::8:d48b]:80: i/o timeout
```

**Pattern**: ALL pod-to-pod communication fails - ICMP, TCP, HTTP, both direct pod IP and ClusterIP services.

### 4. Cilium Reports "OK" Despite Broken Networking

```bash
$ kubectl exec -n kube-system ds/cilium -- cilium status --brief
OK
```

### 5. Cilium Endpoints Show "ready" Despite No Connectivity

```bash
$ kubectl get ciliumendpoints -n flux-system
NAMESPACE     NAME                                    SECURITY IDENTITY   ENDPOINT STATE   IPV6
flux-system   kustomize-controller-57bbd7c-fdtpk      44187               ready            fd00:101:224:7::970b
flux-system   source-controller-6ccfd78764-rzfnk      41034               ready            fd00:101:224:2::aa96
```

Cilium believes endpoints are healthy, but they cannot communicate.

## Current Cilium Configuration

**File**: `kubernetes/apps/networking/cilium/app/values.yaml`

### Critical Settings

```yaml
# Routing mode
routingMode: native
autoDirectNodeRoutes: true
directRoutingSkipUnreachable: true
endpointRoutes:
  enabled: false  # Use per-node CIDR routes instead of per-endpoint

# MTU (underlying VXLAN network)
mtu: 1450

# Native routing CIDRs
ipv4NativeRoutingCIDR: 10.101.0.0/16
ipv6NativeRoutingCIDR: fd00:101::/48

# Pod CIDRs (allocated per-node as /80 subnets from /60)
# IPv6: fd00:101:224::/60 (16 nodes max, /80 per node)
# IPv4: 10.101.224.0/19 (512 /27 subnets, 30 IPs per node)

# Masquerading
enableIPv4Masquerade: false
enableIPv6Masquerade: true  # Required for cluster stability (crashes without it)

# BPF configuration
bpf:
  masquerade: false          # BPF masquerading disabled
  lbMode: snat               # Service load balancing uses SNAT
  lbModeAnnotation: true     # Allow per-service override
  lbExternalClusterIP: true
  hostLegacyRouting: true    # CHANGED FROM false - using legacy routing

# Socket LB
socketLB:
  enabled: true
  hostNamespaceOnly: true    # CHANGED FROM false - restrict to host namespace

# kube-proxy replacement
kubeProxyReplacement: true
```

### Network Architecture

- **Cluster**: Talos Linux 1.9.x, Kubernetes 1.32.x
- **Nodes**: 6 nodes (3 control plane, 3 workers)
- **Networking**: Dual-stack, IPv6-first
  - IPv6 ULA: `fd00:101::/48` (cluster), `fd00:101:224::/60` (pods)
  - IPv4: `10.101.0.0/16` (cluster), `10.101.224.0/19` (pods)
  - Node IPs: IPv6 ULA `fd00:101::10-15`
- **Underlying network**: VXLAN (MTU 1450)
- **CNI**: Cilium (no kube-proxy)
- **BGP**: FRR on each node peers with Cilium for LoadBalancer IP advertisement

## Impact

This networking failure blocks:

1. **Flux reconciliation**: kustomize-controller cannot reach source-controller
2. **Spegel P2P mesh**: libp2p connections timeout (why Spegel was removed)
3. **cert-manager**: ClusterIP timeouts (eventually stabilizes after restarts)
4. **external-secrets**: ClusterIP timeouts (eventually stabilizes after restarts)

**Some services work**:
- CoreDNS responds to DNS queries
- Pods can reach external internet
- Host network pods function
- Node-to-node connectivity works

## What Changed

### Recent Configuration Changes

1. **Removed Spegel** from bootstrap due to libp2p networking failures
2. **Changed `bpf.hostLegacyRouting`**: `false` → `true`
3. **Changed `socketLB.hostNamespaceOnly`**: `false` → `true`
4. **Set `bpf.masquerade`**: `false` (was `true` previously)

### Historical Context

**CRITICAL**: The user reports that networking was broken when running in **hybrid mode** (`hostLegacyRouting: true`) as well, not just direct mode. This means:
- Reverting to hybrid mode will NOT fix the issue
- The root cause is not `hostLegacyRouting` itself
- Common denominators between modes need investigation:
  - `socketLB` configuration
  - `enableIPv6Masquerade: true`
  - `bpf.lbMode: snat`
  - IPv6 ULA networking
  - BPF masquerading interaction with native routing

## NetworkPolicies

**Namespace**: `flux-system` has NetworkPolicies:

```yaml
# allow-egress
spec:
  egress:
  - {}  # Allow all egress
  ingress:
  - from:
    - podSelector: {}  # Allow from all pods in same namespace
  podSelector: {}  # Apply to all pods
  policyTypes:
  - Ingress
  - Egress
```

These appear permissive for intra-namespace communication.

## Diagnostic Questions for Gemini

1. **Why does ALL pod-to-pod traffic fail** (even ICMP ping) despite Cilium reporting "OK"?

2. **What configuration setting could cause this** that would apply in BOTH hybrid and direct routing modes?
   - Is there a BPF map initialization failure?
   - Could IPv6 masquerading be breaking pod-to-pod ULA traffic?
   - Is there a BPF program load order issue?

3. **Why do Cilium endpoints show "ready"** when they have zero connectivity?
   - Does Cilium only check local endpoint health, not connectivity?

4. **Could the issue be**:
   - **MTU/fragmentation**: 1450 MTU insufficient for IPv6 headers?
   - **IPv6 ULA routing**: BPF not handling ULA-to-ULA correctly?
   - **Connection tracking**: CT maps corrupted or not populated?
   - **BPF program conflicts**: Multiple BPF programs interfering?
   - **IPv6 masquerading + native routing**: Incompatible combination?

5. **Why does enabling `bpf.masquerade: true` break things**:
   - Should `bpf.masquerade` be `true` or `false` for native routing with IPv6 ULA?
   - Is there a conflict between `bpf.masquerade` and `enableIPv6Masquerade`?

6. **Socket LB configuration**:
   - Does `socketLB.hostNamespaceOnly: true` prevent pod-to-pod datapath from working?
   - Should Socket LB be disabled entirely?

7. **Could disabling IPv6 masquerading fix it**?
   - User reports cluster crashes without `enableIPv6Masquerade: true`
   - Why is it required, and how does it interact with pod-to-pod ULA traffic?

## What We've Tried

1. ✅ Changed `socketLB.hostNamespaceOnly: false` → `true` (did NOT fix)
2. ✅ Changed `bpf.hostLegacyRouting: false` → `true` (did NOT fix)
3. ✅ Removed Spegel (workaround, not a fix)
4. ✅ Set `bpf.masquerade: false` (current state)
5. ❌ Attempted to disable IPv6 masquerading → Cilium pods crash

## Expected Behavior

Pod-to-pod communication should work natively within the ULA CIDR (`fd00:101::/48`) without any BPF masquerading or NAT, using direct kernel routing.

## Request for Gemini

Please analyze this complete networking failure and provide:

1. **Root cause identification**: What Cilium configuration setting(s) break pod-to-pod connectivity in both hybrid and direct modes?

2. **Configuration fixes**: Specific Cilium values.yaml changes to restore pod-to-pod networking

3. **Explanation**: Why does Cilium report healthy while connectivity is broken?

4. **Diagnostic commands**: How to verify BPF datapath is functioning correctly

5. **IPv6 ULA specifics**: Any known issues with Cilium + IPv6 ULA + native routing?

## Additional Context

- **Talos version**: 1.9.x
- **Kubernetes version**: 1.32.x
- **Cilium version**: 1.18.x (installed via Talos inline manifests during bootstrap)
- **No custom CNI plugins**: Only Cilium (Istio CNI will be added later for Ambient mesh)
- **forwardKubeDNSToHost**: Enabled in Talos machine config (Legacy Mode)

## Files Referenced

- Cilium config: `kubernetes/apps/networking/cilium/app/values.yaml`
- Talos config: `terraform/infra/modules/talos_config/main.tf`
- Documentation: `docs/GEMINI_CILIUM_DIRECT_MODE_NETWORKING_ISSUE.md` (previous Spegel issue)
