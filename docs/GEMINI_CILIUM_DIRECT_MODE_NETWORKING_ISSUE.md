# Cilium Direct Mode Networking Issue - Detailed Analysis Request

## Executive Summary

I need help diagnosing and fixing critical networking issues in a Talos Kubernetes cluster running Cilium in direct mode (`hostLegacyRouting: false`, `bpf.masquerade: true`). The cluster has two specific networking failures:

1. **Spegel P2P mesh completely broken**: All 6 spegel pods fail to establish libp2p connections (error: "failed to negotiate security protocol: context deadline exceeded")
2. **External-secrets ClusterIP timeouts**: Had 5 restarts with timeout errors connecting to Kubernetes API ClusterIP, eventually stabilized

## Cluster Environment

### Infrastructure
- **Platform**: Talos Linux v1.12.1
- **Kubernetes**: v1.34.1
- **CNI**: Cilium (direct mode)
- **Nodes**: 6 total (3 control plane: solcp01-03, 3 workers: solwk01-03)
- **Network**: IPv6-first dual-stack (IPv6 ULA primary, IPv4 secondary)

### Network Configuration
```yaml
# Pod CIDR
IPv6: fd00:101:224::/60  # ULA (Unique Local Address)
IPv4: 10.101.224.0/20

# Service CIDR
IPv6: fd00:101:96::/108  # ULA
IPv4: 10.101.96.0/20

# Node IPs
Control Plane: fd00:101::11, fd00:101::12, fd00:101::13
Workers: fd00:101::21, fd00:101::22, fd00:101::23

# Kubernetes API ClusterIP
fd00:101:96::1:443
```

### Talos Configuration

**File**: `terraform/infra/modules/talos_config/main.tf`

**Line 95** - Host DNS configuration (required for Cilium direct mode):
```hcl
hostDNS = {
  enabled              = true # Required for Talos Helm controller
  forwardKubeDNSToHost = false # Disabled for Cilium BPF Host Routing (Direct Mode)
}
```

**Line 100-102** - Cluster network configuration:
```hcl
common_cluster_network = {
  cni            = { name = "none" }                              # Cilium installed via inline manifests
  podSubnets     = [var.pod_cidr_ipv6, var.pod_cidr_ipv4]         # IPv6 first-class
  serviceSubnets = [var.service_cidr_ipv6, var.service_cidr_ipv4] # IPv6 first-class, dual-stack enabled
}
```

## Cilium Configuration

**File**: `kubernetes/apps/networking/cilium/app/values.yaml`

### Socket Load Balancing (Lines 18-20)
```yaml
socketLB:
  enabled: true              # Enable socket-level load balancing
  hostNamespaceOnly: false   # Apply to all namespaces, not just host
```

### IPv6 Masquerading (Lines 28-32)
```yaml
enableIPv4Masquerade: false  # Keep false - will remove IPv4 eventually
enableIPv6Masquerade: true   # Enabled: Masquerade ULA Pod traffic to GUA Internet
ipv4NativeRoutingCIDR: 10.101.0.0/16
ipv6NativeRoutingCIDR: fd00:101::/48
```

### BPF Configuration (Lines 61-73)
```yaml
bpf:
  masquerade: true
  lbMode: snat
  lbModeAnnotation: true
  lbExternalClusterIP: true
  mapDynamicSizeRatio: 0.005
  preallocateMaps: true
  hostLegacyRouting: false  # Direct mode - pure BPF routing
  tproxy: true
```

### Host Routing (Lines 74-77)
```yaml
enableHostLegacyRouting: false  # Must match bpf.hostLegacyRouting
routingMode: native
autoDirectNodeRoutes: true
```

### Complete Cilium values.yaml
<details>
<summary>Full configuration file (click to expand)</summary>

```yaml
---
autoDirectNodeRoutes: true
bandwidthManager:
  enabled: true
  bbr: true
bgpControlPlane:
  enabled: true
bpf:
  masquerade: true
  lbMode: snat
  lbModeAnnotation: true
  lbExternalClusterIP: true
  mapDynamicSizeRatio: 0.005
  preallocateMaps: true
  hostLegacyRouting: false
  tproxy: true
cluster:
  id: 101
  name: cluster-101
cni:
  exclusive: false
enableHostLegacyRouting: false
enableIPv4Masquerade: false
enableIPv6Masquerade: true
enableRuntimeDeviceDetection: true
endpointRoutes:
  enabled: true
hubble:
  enabled: false
ipam:
  mode: kubernetes
ipv4NativeRoutingCIDR: 10.101.0.0/16
ipv6:
  enabled: true
ipv6NativeRoutingCIDR: fd00:101::/48
k8sServiceHost: fd00:101::fffe
k8sServicePort: 7445
kubeProxyReplacement: true
localRedirectPolicy: true
operator:
  replicas: 1
rollOutCiliumPods: true
routingMode: native
securityContext:
  capabilities:
    ciliumAgent:
      - CHOWN
      - KILL
      - NET_ADMIN
      - NET_RAW
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RESOURCE
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
    cleanCiliumState:
      - NET_ADMIN
      - SYS_ADMIN
      - SYS_RESOURCE
socketLB:
  enabled: true
  hostNamespaceOnly: false
```
</details>

## Problem 1: Spegel P2P Mesh Failure

### Spegel Architecture
Spegel is a distributed container registry mirror using libp2p for P2P communication:
- **P2P Port**: TCP 5001 (libp2p protocol with TLS handshake)
- **Registry Port**: TCP 5000 (OCI registry API)
- **Service**: Headless service `spegel-bootstrap` for P2P discovery
- **Protocol**: libp2p with custom TLS negotiation

### Observed Symptoms

**Pod Status** (all 6 spegel DaemonSet pods):
```
spegel-2v7gb (solcp02):  1/1 Running, 0 restarts  ✅ Appears healthy
spegel-88c6z (solwk03):  1/1 Running, 0 restarts  ✅ Appears healthy
spegel-jxnd6 (solcp03):  1/1 Running, 0 restarts  ✅ Appears healthy
spegel-tz777 (solwk02):  1/1 Running, 0 restarts  ✅ Appears healthy
spegel-2t2s5 (solcp01):  0/1 Running, 0 restarts  ❌ Not ready
spegel-cn569 (solwk01):  0/1 Running, 0 restarts  ❌ Not ready
```

### Error Logs (from ALL pods, including "healthy" ones)

**Initial Connection Attempts** (first 5 seconds):
```json
{"time":"2026-02-11T22:17:31.786636422Z","level":"ERROR","source":{"function":"github.com/spegel-org/spegel/pkg/routing.bootstrapFunc.func1","file":"github.com/spegel-org/spegel/pkg/routing/p2p.go","line":333},"msg":"could not get peer id","logger":"p2p","err":"failed to dial: failed to dial 92B: all dials failed\n  * [/ip6/fd00:101:224:1::ceba/tcp/5001] failed to negotiate security protocol: context deadline exceeded"}
```

**Retry Attempts** (after 10+ seconds):
```json
{"time":"2026-02-11T22:17:36.784929322Z","level":"ERROR","source":{"function":"github.com/spegel-org/spegel/pkg/routing.bootstrapFunc.func1","file":"github.com/spegel-org/spegel/pkg/routing/p2p.go","line":333},"msg":"could not get peer id","logger":"p2p","err":"failed to dial: context deadline exceeded"}

{"time":"2026-02-11T22:17:36.785083185Z","level":"INFO","source":{"function":"github.com/spegel-org/spegel/pkg/routing.bootstrapFunc.func1","file":"github.com/spegel-org/spegel/pkg/routing/p2p.go","line":340},"msg":"no bootstrap nodes found","logger":"p2p"}
```

**Dial Backoff** (after 15+ seconds):
```json
{"time":"2026-02-11T22:17:45.427276415Z","level":"ERROR","source":{"function":"github.com/spegel-org/spegel/pkg/routing.bootstrapFunc.func1","file":"github.com/spegel-org/spegel/pkg/routing/p2p.go","line":333},"msg":"could not get peer id","logger":"p2p","err":"failed to dial: failed to dial 92B: all dials failed\n  * [/ip6/fd00:101:224::18bc/tcp/5001] dial backoff\n  * [/ip6/fd00:101:224:1::ceba/tcp/5001] dial backoff\n  * [/ip6/fd00:101:224:2::769b/tcp/5001] dial backoff\n  * [/ip6/fd00:101:224:3::30c7/tcp/5001] dial backoff\n  * [/ip6/fd00:101:224:4::569d/tcp/5001] dial backoff"}
```

### Key Observations

1. **Initial error**: `"failed to negotiate security protocol: context deadline exceeded"`
   - Suggests TLS handshake is timing out
   - Occurs on IPv6 pod-to-pod connections over TCP 5001

2. **All pods affected**: Even pods showing "1/1 Running" have the same errors in logs
   - 4 pods pass startup probes despite having NO peer connections
   - 2 pods fail startup probes and never become ready
   - **Reality**: 0/6 pods have working P2P mesh (spegel is completely non-functional)

3. **Consistent failure pattern**: Every peer connection attempt fails
   - No successful connections found in any logs
   - libp2p enters exponential backoff ("dial backoff")
   - Error pattern identical across all nodes

4. **Pod IPs being dialed**: All valid pod IPs in the pod CIDR:
   ```
   fd00:101:224::18bc (solcp01)
   fd00:101:224::1e25 (solcp01 - old pod)
   fd00:101:224:1::ceba (solwk02)
   fd00:101:224:2::769b (solwk03)
   fd00:101:224:3::30c7 (solcp03)
   fd00:101:224:4::569d (solcp02)
   fd00:101:224:5::5cce (solwk01 - old pod)
   ```

## Problem 2: External-Secrets ClusterIP Timeout

### External-Secrets Architecture
- **Purpose**: Syncs secrets from 1Password Connect to Kubernetes
- **Dependency**: Kubernetes API server at ClusterIP `[fd00:101:96::1]:443`
- **Protocol**: HTTPS (TLS over TCP)

### Observed Symptoms

**Pod Status**:
```
external-secrets-78b85b787-nh7kc: 1/1 Running, 5 restarts (8m15s ago)
```

**Error Logs** (during first 5 restarts):
```json
{"error":"failed to determine if *v1.Secret is namespaced: failed to get restmapping: failed to get server groups: Get \"https://[fd00:101:96::1]:443/api\": dial tcp [fd00:101:96::1]:443: i/o timeout"}
```

**Outcome**: Eventually stabilized after 5 restarts

### Key Observations

1. **ClusterIP connectivity issue**: Pod couldn't reach Kubernetes API ClusterIP
2. **Self-healing behavior**: After 5 restarts (likely connection tracking state expiration), connections succeeded
3. **IPv6 ULA ClusterIP**: Target is `[fd00:101:96::1]:443` (within service CIDR `fd00:101:96::/108`)

## Cilium Status on Nodes

**Checked on solwk01, solcp01, solwk03, solcp02** (all show identical configuration):

```
Routing:                 Network: Native   Host: BPF
Masquerading:            BPF   [dummy0, ens18, ens19.30]   10.101.0.0/16 fd00:101::/48 [IPv4: Disabled, IPv6: Enabled]
```

All nodes have:
- BPF-based host routing (direct mode)
- BPF masquerading enabled
- Identical network configuration

## Hypothesis from Initial Investigation

### Issue 1: Socket LB Intercepting libp2p Protocol
- `socketLB.hostNamespaceOnly: false` applies socket LB to ALL pod namespaces
- Socket LB intercepts connect() syscalls
- libp2p's custom TLS handshake requires unmodified packet flow
- Interception may be rewriting packets before TLS negotiation completes

### Issue 2: IPv6 Masquerading Internal Traffic
- `enableIPv6Masquerade: true` is masquerading internal pod → ClusterIP connections
- Should only masquerade external/egress traffic (pod → internet)
- Internal service traffic (pod → ClusterIP) should not be masqueraded
- Causes connection tracking conflicts and timeouts

### Issue 3: SNAT Mode Connection Tracking
- `bpf.lbMode: snat` rewrites source IPs aggressively
- Combined with `bpf.masquerade: true`, causes double SNAT
- Connection tracking state corruption for protocols with embedded addresses

## Questions for Analysis

1. **Socket LB Scope**: Is `socketLB.hostNamespaceOnly: false` the correct setting for Cilium direct mode? Should it be `true` to avoid intercepting application pod connections?

2. **IPv6 Masquerading**: Should `enableIPv6Masquerade: true` apply to:
   - Pod → Pod traffic within cluster? (I think NO)
   - Pod → ClusterIP traffic? (I think NO)
   - Pod → Internet traffic? (I think YES)

   How do we configure masquerading to ONLY apply to external egress?

3. **BPF Load Balancer Mode**: Is `bpf.lbMode: snat` compatible with:
   - Protocols requiring TLS negotiation (like libp2p)?
   - IPv6 ULA networking?
   - Should we use `hybrid` mode instead?

4. **libp2p Compatibility**: Are there known issues with Cilium socket LB and libp2p protocol? Does libp2p require specific Cilium configuration?

5. **Connection Tracking**: Could the combination of:
   - `socketLB.enabled: true` + `hostNamespaceOnly: false`
   - `enableIPv6Masquerade: true`
   - `bpf.masquerade: true` + `bpf.lbMode: snat`

   Be causing connection tracking conflicts that corrupt protocol state?

6. **IPv6 ULA Routing**: Are there specific Cilium configurations needed for IPv6 ULA (fd00::/8) networking in direct mode?

## Proposed Configuration Changes

Based on initial analysis, I'm considering:

### Change 1: Restrict Socket LB to Host Namespace
```yaml
socketLB:
  enabled: true
  hostNamespaceOnly: true  # ← Change from false
```

### Change 2: Disable IPv6 Masquerading for Internal Traffic
```yaml
enableIPv6Masquerade: false  # ← Change from true
```

**Concern**: Will this break pod → internet egress? How do we ensure pods can still reach external destinations?

### Change 3: Switch to Hybrid Load Balancer Mode
```yaml
bpf:
  masquerade: true
  lbMode: hybrid  # ← Change from snat
  lbModeAnnotation: true
  hostLegacyRouting: false
```

## Request for Gemini

Please analyze this networking issue and provide:

1. **Root cause analysis**: What exactly is breaking the networking?
2. **Configuration recommendations**: What specific Cilium settings should be changed?
3. **Verification approach**: How to validate fixes work without breaking other functionality?
4. **Alternative solutions**: If proposed changes are incorrect, what should we do instead?
5. **Upstream compatibility**: Are these issues known in Cilium + Talos + IPv6 ULA environments?

## Additional Context

- **No Network Policies**: Only one NetworkPolicy exists (flux-operator), shouldn't affect spegel or external-secrets
- **Cilium Status**: All CiliumNode resources show healthy
- **Node Connectivity**: All 6 nodes are Ready, no node network issues
- **Other Pods**: Most other workloads function correctly (cert-manager, onepassword, volsync all working)
- **CoreDNS**: Running with default configuration, no custom forwarding (cleaned up per previous DNS issue resolution)

### CRITICAL: Networking Was Broken in Hybrid Mode Too

**Important context**: The user reports that networking issues existed when running Cilium in **hybrid mode** (`hostLegacyRouting: true`) as well, not just in direct mode. This means:

1. **Reverting to hybrid mode is NOT a solution** - the same networking problems occurred
2. **The issue may not be specific to direct mode** - it could be related to other Cilium settings that apply to both modes
3. **Common denominators between modes** to investigate:
   - `socketLB.enabled: true` + `socketLB.hostNamespaceOnly: false` (applies to both modes)
   - `enableIPv6Masquerade: true` (applies to both modes)
   - `bpf.lbMode: snat` (applies to both modes)
   - IPv6 ULA networking configuration
   - BPF masquerading settings

This suggests the root cause is likely one of the settings that was enabled in BOTH hybrid and direct mode, rather than the `hostLegacyRouting` setting itself.

## References

- Cilium Direct Routing Mode: https://docs.cilium.io/en/stable/network/concepts/routing/#direct-routing-mode
- Cilium Socket-Based Load Balancing: https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#socket-loadbalancer-bypass-in-pod-namespace
- Spegel Architecture: https://github.com/spegel-org/spegel (libp2p-based P2P registry mirror)
