# IPv6 Cross-Node Pod Routing Broken — Cilium 1.19 + Talos 1.12 + Dual-Stack

## Goal

I have a 6-node Talos Linux Kubernetes cluster (3 control planes, 3 workers) running Cilium 1.19.0 as the CNI in native routing mode with dual-stack networking. Services are IPv6-only (`ipFamilies: ["IPv6"]`). I need IPv6 pod-to-pod traffic to work across nodes so that services like Flux can function.

## The Problem

**IPv6 cross-node pod-to-pod traffic is completely broken. IPv4 cross-node works fine.**

Flux's kustomize-controller (on solwk03) cannot reach source-controller (on solwk02) via the IPv6 service ClusterIP. The TCP SYN packets leave solwk03 but never arrive at solwk02.

## Evidence

### 1. Service Configuration
```
Service: source-controller  ClusterIP fd00:101:96::9:f576  Port 80/TCP
Endpoint: [fd00:101:224:1::2f9e]:9090
ipFamilies: ["IPv6"], ipFamilyPolicy: SingleStack
```

### 2. Pod Placement
```
kustomize-controller  fd00:101:224:2::3ac8  solwk03 (pod CIDR fd00:101:224:2::/64)
source-controller     fd00:101:224:1::2f9e  solwk02 (pod CIDR fd00:101:224:1::/64)
```
Pods are dual-stack (have both IPv4 and IPv6 addresses).

### 3. Connectivity Tests
| Test | Result |
|------|--------|
| Same-node (solwk02 pod → source-controller via IPv6 pod IP) | **WORKS** |
| Cross-node (solwk03 pod → source-controller via IPv6 pod IP) | **TIMEOUT** |
| Cross-node (solwk03 pod → source-controller via IPv4 pod IP 10.101.225.96:9090) | **WORKS** |
| source-controller localhost:9090 | **WORKS** |

### 4. Hubble Observations
**On solwk03 (source node):** SYN packets are `to-network FORWARDED` — they leave the BPF datapath:
```
kustomize-controller:47972 -> source-controller:9090 policy-verdict:none ALLOWED (TCP Flags: SYN)
kustomize-controller:47972 -> source-controller:9090 to-network FORWARDED (TCP Flags: SYN)
# SYN retransmit 7 seconds later — no SYN-ACK received:
kustomize-controller:47972 -> source-controller:9090 to-network FORWARDED (TCP Flags: SYN)
```

**On solwk02 (destination node):** No SYN packets from kustomize-controller are seen at all. Only local traffic (from fd00:101:224:1::9097, a local pod/health endpoint) reaches source-controller.

**Conclusion: Hubble claims packets are forwarded on solwk03, but they never arrive at solwk02.**

### 5. Packet Captures (talosctl pcap) — CRITICAL FINDING
**On solwk03 ens18:** Pod-to-node-IP IPv6 traffic DOES appear on the wire (e.g., `fd00:101:224:2::2a2f → fd00:101::12:6443` for kube-apiserver). **But pod-to-remote-pod-IP traffic (fd00:101:224:2::3ac8 → fd00:101:224:1::2f9e) NEVER appears on ens18.**

**On solwk02 ens18:** No pod CIDR IPv6 packets from solwk03 arrive. Only node-IP traffic (fd00:101::22 ↔ fd00:101::12) is seen.

**Conclusion: BPF host routing on solwk03 reports `to-network FORWARDED` but the packets never actually leave ens18. The BPF `bpf_fib_lookup()` helper likely fails for IPv6 routes through a gateway (pod CIDR → via next-hop) but succeeds for directly connected destinations (node IPs on the same L2 segment).**

### 6. Hubble Drops
Only 1 unrelated drop (ICMPv6 RouterSolicitation "Invalid source ip"). No drops for cross-node pod traffic.

### 6. Routes on solwk03
Routes look correct — Cilium installed direct node routes:
```
fd00:101:224::/64    via fd00:101::12  dev ens18  (solcp02)
fd00:101:224:1::/64  via fd00:101::22  dev ens18  (solwk02) ← source-controller is here
fd00:101:224:2::/64  dev cilium_host   (local)
fd00:101:224:3::/64  via fd00:101::21  dev ens18  (solwk01)
fd00:101:224:4::/64  via fd00:101::11  dev ens18  (solcp01)
fd00:101:224:5::/64  via fd00:101::13  dev ens18  (solcp03)
```

### 7. Cilium Status
```
Cilium:              Ok   1.19.0 (v1.19.0-7c6667e1)
KubeProxyReplacement: True
Routing:             Network: Native   Host: BPF
Cluster health:      6/6 reachable
IPAM:                IPv4: 10.101.229.0/24, IPv6: fd00:101:224:5::/64
Masquerading:        BPF [dummy0, ens18] 10.101.0.0/16 fd00:101::/48
```

### 8. ip6tables on solwk02
All IPv6 FORWARD counters are 0 (expected with BPF host routing, but also confirms no packets reach kernel forwarding):
```
Chain CILIUM_FORWARD:
 0  0  ACCEPT  cilium_host  (any->cluster)
 0  0  ACCEPT  cilium_host  (cluster->any nodeport)
 0  0  ACCEPT  lxc+         (cluster->any)
 0  0  ACCEPT  cilium_net   (cluster->any nodeport)
```

### 9. Other Details
- IPv6 forwarding is enabled: `net.ipv6.conf.all.forwarding = 1`
- IPv4 rp_filter is 0 on ens18
- Kernel: `6.18.2-talos`
- Cilium node list shows correct CIDR assignments for all nodes
- No nftables binary in Cilium container (Talos may have host-level nftables rules)

## Cluster Configuration

### Network CIDRs
```
Pod CIDRs:     fd00:101:224::/60 (IPv6), 10.101.224.0/20 (IPv4)
Service CIDRs: fd00:101:96::/108 (IPv6), 10.101.96.0/24 (IPv4)
Node IPs:      fd00:101::11-23 (IPv6), 10.101.0.11-23 (IPv4)
```

### Cilium Values (values.yaml)
```yaml
kubeProxyReplacement: true
socketLB:
  enabled: false
ipv4:
  enabled: true
ipv6:
  enabled: true
enableIPv4Masquerade: true
enableIPv6Masquerade: true
ipam:
  mode: kubernetes
k8s:
  requireIPv6PodCIDR: true
routingMode: native
autoDirectNodeRoutes: true
directRoutingSkipUnreachable: false
endpointRoutes:
  enabled: false
mtu: 1450  # Underlying network is VXLAN
ipv4NativeRoutingCIDR: 10.101.0.0/16
ipv6NativeRoutingCIDR: fd00:101::/48
bpf:
  masquerade: true
  lbMode: snat
  hostLegacyRouting: false  # BPF host routing enabled
  preallocateMaps: true
dnsProxy:
  enabled: true
bgpControlPlane:
  enabled: true
envoy:
  enabled: true
gatewayAPI:
  enabled: true
```

### Talos Config (relevant parts)
```yaml
cluster:
  network:
    cni:
      name: none  # Cilium manages CNI
    podSubnets:
      - fd00:101:224::/60
      - 10.101.224.0/20
    serviceSubnets:
      - fd00:101:96::/108
      - 10.101.96.0/24
```
- Talos v1.12.1, Kubernetes v1.34.1
- Underlying hypervisor network uses VXLAN (hence MTU 1450)
- Nodes are on the same L2 segment (10.101.0.0/24, fd00:101::/64)

## Root Cause Analysis

Based on the evidence, the problem is **definitively in Cilium's BPF host routing (`bpf.hostLegacyRouting: false`)** on the source node. Here's why:

1. **Packets never leave ens18** — pcap on solwk03's ens18 shows no pod-to-remote-pod IPv6 traffic, despite Hubble claiming `to-network FORWARDED`
2. **Pod-to-node-IP IPv6 works** — traffic from pods to kube-apiserver (node IPs like fd00:101::12) traverses ens18 fine
3. **IPv4 cross-node works** — same physical path, same BPF programs, but IPv4 succeeds
4. **NDP is fine** — solwk03 has a valid, REACHABLE NDP entry for solwk02 (fd00:101::22 → MAC bc:24:11:4d:fb:82)
5. **Routes are correct** — `fd00:101:224:1::/64 via fd00:101::22 dev ens18` is properly installed

**The BPF `bpf_fib_lookup()` helper appears to fail for IPv6 routes that go through a gateway (pod CIDR routes via next-hop), while succeeding for directly connected destinations (node IPs on the same L2 segment). This causes the BPF program to silently drop the packet while still reporting it as forwarded in Hubble.**

### Key differences between working and broken paths:
- **Working:** Pod → fd00:101::12 (node IP, directly connected on ens18 subnet)
- **Broken:** Pod → fd00:101:224:1::2f9e (remote pod IP, routed via fd00:101::22 gateway)

## Likely Fix Options

1. **Set `bpf.hostLegacyRouting: true`** — Falls back to kernel routing stack for host-level forwarding. This should fix IPv6 cross-node routing since the kernel routes are correct. Performance impact is minimal for most workloads.

2. **File a Cilium bug** — This appears to be a regression or limitation in `bpf_fib_lookup()` with IPv6 + native routing + autoDirectNodeRoutes on kernel 6.18.2.

3. **Switch services to dual-stack or IPv4-preferred** — Workaround that avoids the broken IPv6 service path while keeping IPv6 for everything else.

## What I Need Help With

1. Is this a known Cilium 1.19 / kernel 6.18 issue with `bpf_fib_lookup()` and IPv6 gateway routes?
2. Is setting `bpf.hostLegacyRouting: true` the correct fix, or is there a more targeted solution (e.g., a Cilium config or kernel sysctl)?
3. Could `endpointRoutes.enabled: true` work around this by installing per-endpoint routes instead of per-node CIDR routes?
4. Are there any known interactions between Cilium's BPF masquerading and IPv6 FIB lookups that could cause this?

### Additional Context
- Cilium attach mode: TCX (so `tc filter show` doesn't display BPF programs)
- Kernel: 6.18.2-talos (very new, possible BPF regression)
- Talos dmesg shows `nftables chains updated {"chains": []}` — no Talos-level nftables rules blocking traffic
- Cilium health probes report 6/6 reachable (but these may use IPv4)

You have full access to the config files if you need to see more details.
