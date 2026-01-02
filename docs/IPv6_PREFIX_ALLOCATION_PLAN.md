# IPv6 Prefix Allocation Plan
## Semantic Segregation: fc00::/8 vs fd00::/8

**Last Updated:** 2025-01-09
**Status:** Production (Current Addressing Documented)

---

## Design Principle

This document defines the IPv6 addressing scheme for our infrastructure based on **semantic separation** between internal fast-ring traffic and external routable traffic.

### Semantic Allocation Strategy

- **fc00::/8** → Internal fast-ring traffic (Ceph storage, VM mesh networks, pod-to-pod communication)
  - High bandwidth (10G mesh links)
  - MTU 8950-9000
  - Not routed to internet
  - Optimized for speed and latency

- **fd00::/8** → External routable traffic (management, internet egress, BGP-advertised services)
  - Standard bandwidth (1G uplinks)
  - MTU 1500
  - Routable via RouterOS
  - Internet-accessible services

### Routing Strategy

**IMPORTANT:** We use **specific /64 route entries**, NOT broad /8 aggregates.

For non-FRR VMs with two interfaces (eth0=fast-ring, eth1=external), routing is configured with specific prefixes:

```bash
# Fast-ring traffic via eth0 (mesh interface)
ip -6 route add fc00:20::/64 via fc00:101::fffe dev eth0       # Ceph public
ip -6 route add fc00:21::/64 via fc00:101::fffe dev eth0       # Ceph cluster
ip -6 route add fc00:101::/64 dev eth0                         # Local mesh

# External traffic via eth1 (egress interface)
ip -6 route add fd00:10::/64 via fd00:101::fffe dev eth1       # PVE management
ip -6 route add fd00:101::/64 dev eth1                         # Local egress
ip -6 route add default via fd00:101::fffe dev eth1            # Default route
```

**Why specific routes instead of fc00::/8 and fd00::/8?**
- More explicit control over traffic paths
- Prevents unintended routing loops
- Makes troubleshooting easier (can see exactly which networks go where)
- Allows for exceptions (e.g., some fd00:: networks might need different paths)

---

## fc00::/8 Block - Internal Fast-Ring Traffic

### fc00:20::/64 - Ceph Public Network
| IP | Host | Services |
|----|------|----------|
| `fc00:20::1/64` | pve01 | Ceph MON, MGR, OSD client communication |
| `fc00:20::2/64` | pve02 | Ceph MON, MGR, OSD client communication |
| `fc00:20::3/64` | pve03 | Ceph MON, MGR, OSD client communication |

**Monitor Endpoints:** `[fc00:20::1]:6789`, `[fc00:20::2]:6789`, `[fc00:20::3]:6789`
**Interface:** `dummy_underlay` on PVE hosts, routed via mesh links
**Purpose:** Client → Ceph traffic (VMs, K8s CSI drivers, Proxmox storage)
**MTU:** 9000
**Access:** Via static routes on mesh links or anycast gateway

### fc00:21::/64 - Ceph Cluster Network
| IP | Host | Purpose |
|----|------|---------|
| `fc00:21::1/64` | pve01 | OSD replication, recovery, heartbeat |
| `fc00:21::2/64` | pve02 | OSD replication, recovery, heartbeat |
| `fc00:21::3/64` | pve03 | OSD replication, recovery, heartbeat |

**Interface:** `dummy_underlay` on PVE hosts, routed via mesh links
**Purpose:** Internal OSD-to-OSD communication (never exposed to VMs)
**MTU:** 9000

### fc00:101::/64 - K8s Node Mesh Network (VXLAN 100101)
| IP | Host | Interface | Purpose |
|----|------|-----------|---------|
| `fc00:101::fffe/64` | Anycast GW | vnet101 (all PVE) | SDN anycast gateway |
| `fc00:101::11/64` | solcp011 | eth0 | Mesh interface, Cilium iBGP, pod traffic |
| `fc00:101::12/64` | solcp012 | eth0 | Mesh interface, Cilium iBGP, pod traffic |
| `fc00:101::13/64` | solcp013 | eth0 | Mesh interface, Cilium iBGP, pod traffic |
| `fc00:101::21/64` | solwk021 | eth0 | Mesh interface, Cilium iBGP, pod traffic |
| `fc00:101::22/64` | solwk022 | eth0 | Mesh interface, Cilium iBGP, pod traffic |
| `fc00:101::23/64` | solwk023 | eth0 | Mesh interface, Cilium iBGP, pod traffic |

**Proxmox SDN:**
- Zone: `vxevpn01` (EVPN VXLAN)
- VNet: `vnet101`
- VXLAN ID: 100101
- MTU: 8950

**Purpose:** Fast P2P ring for Kubernetes internal traffic
**Use Cases:**
- Cilium iBGP mesh (pod CIDR distribution)
- High-bandwidth pod-to-pod communication
- Direct node-to-node traffic
- IS-IS for loopback reachability

**Routing Protocol:** IS-IS level-2 for loopback distribution

---

## fd00::/8 Block - External Routable Traffic

### fd00:10::/64 - Proxmox Management Network (VLAN 10)
| IP | Host | Interface | Purpose |
|----|------|-----------|---------|
| `fd00:10::1/64` | pve01 | vmbr0.10 | SSH, web UI, API access |
| `fd00:10::2/64` | pve02 | vmbr0.10 | SSH, web UI, API access |
| `fd00:10::3/64` | pve03 | vmbr0.10 | SSH, web UI, API access |
| `fd00:10::4/64` | pve04 | vmbr0.10 | SSH, web UI, API access (future) |
| `fd00:10::fffe/64` | RouterOS | VLAN 10 | Default gateway, DNS, NTP |

**VLAN:** 10 (native on vmbr0)
**MTU:** 1500
**Purpose:** Management and administrative access
**Routing:** Via RouterOS to internet

### fd00:70::/64 - IoT Network (VLAN 70)
| IP | Device | Purpose |
|----|--------|---------|
| `fd00:70::1/64` | Anycast GW | Gateway (all PVE hosts via SDN) |
| `fd00:70::20/64` | Home Assistant | Home automation (via Multus CNI) |
| `fd00:70::21-ff` | IoT devices | Smart home devices |

**VLAN:** 70
**Purpose:** IoT devices, smart home infrastructure
**Routing:** Via RouterOS, internet-accessible

### fd00:90::/64 - VPN Network (VLAN 90)
| IP | Device | Purpose |
|----|--------|---------|
| `fd00:90::1/64` | Anycast GW | Gateway (all PVE hosts via SDN) |
| `fd00:90::10-ff` | VPN clients | Remote access clients |

**VLAN:** 90
**Purpose:** VPN-connected devices
**Routing:** Via RouterOS

### fd00:101::/64 - K8s Node Egress/Management (VLAN 101)
| IP | Host | Interface | Purpose |
|----|------|-----------|---------|
| `fd00:101::fffe/64` | RouterOS | VLAN 101 | Default gateway, BGP peer |
| `fd00:101::11/64` | solcp011 | eth1 | Internet egress, Ansible SSH |
| `fd00:101::12/64` | solcp012 | eth1 | Internet egress, Ansible SSH |
| `fd00:101::13/64` | solcp013 | eth1 | Internet egress, Ansible SSH |
| `fd00:101::21/64` | solwk021 | eth1 | Internet egress, Ansible SSH |
| `fd00:101::22/64` | solwk022 | eth1 | Internet egress, Ansible SSH |
| `fd00:101::23/64` | solwk023 | eth1 | Internet egress, Ansible SSH |

**VLAN:** 101 (tagged on vmbr0)
**MTU:** 1500
**Purpose:**
- Internet egress for nodes
- Ansible management SSH access
- BGP peering to RouterOS
- External service access

**Routing:** Default route via RouterOS gateway

### fd00:200::/64 - NAT64/DNS64 Network (VLAN 200)
| IP | Host | Purpose |
|----|------|---------|
| `fd00:200::64/64` | jool VM | NAT64 gateway, DNS64 resolver |

**VLAN:** 200
**Purpose:** IPv6-only → IPv4 translation
**Services:** Jool NAT64, Unbound DNS64

### fd00:0:0:ffff::/56 - Infrastructure Loopbacks

**Convention:** The `255` sub-prefix is reserved for infrastructure loopbacks and VIPs (following IPv4 tradition where x.x.x.255 is often infrastructure).

#### fd00:0:0:ffff::/64 - Proxmox Infrastructure Loopbacks
| IP | Host | Interface | Purpose |
|----|------|-----------|---------|
| `fd00:0:0:ffff::1/128` | pve01 | dummy_underlay | BGP peering source, router ID |
| `fd00:0:0:ffff::2/128` | pve02 | dummy_underlay | BGP peering source, router ID |
| `fd00:0:0:ffff::3/128` | pve03 | dummy_underlay | BGP peering source, router ID |
| `fd00:0:0:ffff::4/128` | pve04 | dummy_underlay | BGP peering source, router ID (future) |
| `fd00:0:0:ffff::fffe/128` | RouterOS | Loopback | BGP peer for PVE hosts |

**Purpose:** BGP session source IPs, stable identifiers
**BGP Session:** PVE (AS 65001) ↔ RouterOS (AS 65000)
**Protocol:** BGP EVPN L2VPN + IPv6 unicast

#### fd00:255:101::/64 - K8s Infrastructure Loopbacks + VIP
| IP | Host | Interface | Purpose |
|----|------|-----------|---------|
| `fd00:255:101::11/128` | solcp011 | lo | FRR BGP update-source |
| `fd00:255:101::12/128` | solcp012 | lo | FRR BGP update-source |
| `fd00:255:101::13/128` | solcp013 | lo | FRR BGP update-source |
| `fd00:255:101::21/128` | solwk021 | lo | FRR BGP update-source |
| `fd00:255:101::22/128` | solwk022 | lo | FRR BGP update-source |
| `fd00:255:101::23/128` | solwk023 | lo | FRR BGP update-source |
| `fd00:255:101::ac/128` | K8s VIP | virtual | Control plane VIP (health-checked, advertised via FRR) |

**Purpose:**
- BGP session source IPs for FRR → RouterOS
- K8s API server VIP (advertised when healthy)

**BGP Details:**
- Node AS: 65101
- Peer: `fd00:101::fffe` (RouterOS, AS 65000)
- Update source: `fd00:255:101::X` (loopback)
- Next-hop: `fd00:101::X` (egress interface)
- eBGP multihop: 2
- Health check: `/usr/local/bin/vip-health-bgp.sh`

**Advertised Routes:**
- `fd00:255:101::ac/128` (K8s VIP) when healthy
- `fd00:101:cafe::/112` (LoadBalancer pool)

**Reachability:** Static routes on RouterOS pointing to egress IPs:
```routeros
/ipv6/route/add dst-address=fd00:255:101::11/128 gateway=fd00:101::11
/ipv6/route/add dst-address=fd00:255:101::12/128 gateway=fd00:101::12
# ... etc for all nodes
```

---

## Kubernetes Service Networks

### fd00:101:44::/60 - K8s Pod CIDR (Dual-Stack IPv6)
Subdivided into /64 per node by controller-manager:

| Subnet | Node | Size | Purpose |
|--------|------|------|---------|
| `fd00:101:44::/64` | solcp011 | 2^64 IPs | Pods on control plane 1 |
| `fd00:101:45::/64` | solcp012 | 2^64 IPs | Pods on control plane 2 |
| `fd00:101:46::/64` | solcp013 | 2^64 IPs | Pods on control plane 3 |
| `fd00:101:47::/64` | solwk021 | 2^64 IPs | Pods on worker 1 |
| `fd00:101:48::/64` | solwk022 | 2^64 IPs | Pods on worker 2 |
| `fd00:101:49::/64` | solwk023 | 2^64 IPs | Pods on worker 3 |

**Distribution:** Cilium CNI with kube-controller-manager IPAM
**Routing:** Cilium encapsulation (VXLAN or native routing)
**Traffic Path:** Pod traffic flows over fc00:101:: mesh (eth0) for performance

**Note:** Currently using fd00:: prefix (external semantics), but pod-to-pod traffic still uses the fast-ring mesh network due to Cilium's underlay being fc00:101::/64.

**Future Consideration:** Could migrate to fc00:101::/60 block to align semantics with actual traffic path.

### 10.244.0.0/16 - K8s Pod CIDR (Dual-Stack IPv4)
| Subnet | Node | Size |
|--------|------|------|
| `10.244.0.0/24` | solcp011 | 254 IPs |
| `10.244.1.0/24` | solcp012 | 254 IPs |
| `10.244.2.0/24` | solcp013 | 254 IPs |
| `10.244.3.0/24` | solwk021 | 254 IPs |
| `10.244.4.0/24` | solwk022 | 254 IPs |
| `10.244.5.0/24` | solwk023 | 254 IPs |

**Distribution:** Same as IPv6 (kube-controller-manager)
**Purpose:** Dual-stack IPv4 support

### fd00:101:96::/108 - K8s Service CIDR (ClusterIP IPv6)
**Range:** `fd00:101:96::0` - `fd00:101:96::ff:ffff:ffff` (20 bits = ~1 million IPs)

**Purpose:** Internal Kubernetes ClusterIP services
**Routing:** NOT advertised externally (cluster-internal only)
**IPAM:** Kubernetes API server

### 10.96.0.0/12 - K8s Service CIDR (ClusterIP IPv4)
**Range:** `10.96.0.0` - `10.111.255.255` (~1 million IPs)

**Purpose:** Dual-stack IPv4 ClusterIP services
**Routing:** Cluster-internal only

### fd00:101:cafe::/112 - K8s LoadBalancer IP Pool (IPv6)
**Range:** `fd00:101:cafe::1` - `fd00:101:cafe::ffff` (65,534 IPs)

**Purpose:** Externally-accessible Kubernetes services (LoadBalancer type)
**Routing:** Advertised via FRR BGP to RouterOS
**IPAM:** MetalLB or Cilium LB-IPAM

**Cilium BGP Configuration:**
- AS: 65101
- Peer: `fd00:101::fffe` (RouterOS, AS 65000)
- Update source: `fd00:255:101::X` (loopback)
- eBGP multihop: 2
- Service selector: `io.cilium/bgp-announce: "true"` or all LoadBalancers

**Mnemonic:** "cafe" = externally accessible services (like a public café)

**Alternative Semantic Option:** Could use `fd00:101:1b::/112` where "1b" stands for "LoadBalancer" for clearer semantics.

---

## Network Design Patterns

### Two-Interface VMs (Non-K8s)

For VMs with dual interfaces that aren't running FRR:

**Interface Configuration:**
- **eth0:** fc00:101::X/64 (mesh network, gateway fc00:101::fffe)
- **eth1:** fd00:101::X/64 (egress network, gateway fd00:101::fffe)

**Routing Configuration:**
```bash
# Ceph storage via mesh (high-speed path)
ip -6 route add fc00:20::/64 via fc00:101::fffe dev eth0 metric 100
ip -6 route add fc00:21::/64 via fc00:101::fffe dev eth0 metric 100

# Management network via egress
ip -6 route add fd00:10::/64 via fd00:101::fffe dev eth1 metric 100

# Default route via egress
ip -6 route add default via fd00:101::fffe dev eth1
```

**Traffic Flow:**
- Ceph storage access → eth0 (10G mesh)
- Internet/management → eth1 (1G uplink)
- Pod-to-pod (if K8s) → eth0 (high-speed mesh)

### Kubernetes Nodes (With FRR)

K8s nodes run FRR for BGP and use IS-IS for loopback distribution:

**Interface Configuration:**
- **eth0:** fc00:101::X/64 (mesh, anycast gateway fc00:101::fffe)
- **eth1:** fd00:101::X/64 (egress, RouterOS gateway fd00:101::fffe)
- **lo:** fd00:255:101::X/128 (BGP loopback)

**FRR Configuration:**
```frr
# IS-IS for loopback distribution on mesh
router isis SOL-K8S
  net 49.0001.0000.0000.00XX.00
  is-type level-2

interface eth0
  ip router isis SOL-K8S
  ipv6 router isis SOL-K8S

# BGP for external route advertisement
router bgp 65101
  bgp router-id 10.255.101.X
  neighbor fd00:101::fffe remote-as 65000
  neighbor fd00:101::fffe update-source fd00:255:101::X
  neighbor fd00:101::fffe ebgp-multihop 2

  address-family ipv6 unicast
    network fd00:255:101::ac/128  # VIP
    network fd00:101:cafe::/112   # LoadBalancer pool
  exit-address-family
```

**Static Routes:**
```bash
# Ceph via mesh anycast
ip -6 route add fc00:20::/64 via fc00:101::fffe dev eth0 metric 100 onlink
ip -6 route add fc00:21::/64 via fc00:101::fffe dev eth0 metric 100 onlink

# Default via egress
ip -6 route add default via fd00:101::fffe dev eth1
```

---

## RouterOS Configuration

### Static Routes for K8s Loopback Reachability

BGP sessions use loopback IPs as update-source, but next-hop is the egress interface. RouterOS needs static routes to reach the loopbacks:

```routeros
/ipv6/route
add dst-address=fd00:255:101::11/128 gateway=fd00:101::11 comment="solcp011 BGP loopback"
add dst-address=fd00:255:101::12/128 gateway=fd00:101::12 comment="solcp012 BGP loopback"
add dst-address=fd00:255:101::13/128 gateway=fd00:101::13 comment="solcp013 BGP loopback"
add dst-address=fd00:255:101::21/128 gateway=fd00:101::21 comment="solwk021 BGP loopback"
add dst-address=fd00:255:101::22/128 gateway=fd00:101::22 comment="solwk022 BGP loopback"
add dst-address=fd00:255:101::23/128 gateway=fd00:101::23 comment="solwk023 BGP loopback"
```

### BGP Configuration

```routeros
/routing/bgp/connection
add name=solcp011 remote.address=fd00:255:101::11 remote.as=65101 local.role=ebgp multihop=yes
add name=solcp012 remote.address=fd00:255:101::12 remote.as=65101 local.role=ebgp multihop=yes
add name=solcp013 remote.address=fd00:255:101::13 remote.as=65101 local.role=ebgp multihop=yes
add name=solwk021 remote.address=fd00:255:101::21 remote.as=65101 local.role=ebgp multihop=yes
add name=solwk022 remote.address=fd00:255:101::22 remote.as=65101 local.role=ebgp multihop=yes
add name=solwk023 remote.address=fd00:255:101::23 remote.as=65101 local.role=ebgp multihop=yes
```

### BGP Route Filters

Ensure fc00:: prefixes (internal fast-ring) are never accepted from K8s nodes:

```routeros
/routing/filter/rule
add chain=k8s-in rule="if (dst in fc00::/8) { reject }"
add chain=k8s-in rule="if (dst in fd00:101:cafe::/112) { accept }"
add chain=k8s-in rule="if (dst in fd00:255:101::ac/128) { accept }"
add chain=k8s-in rule="reject"
```

Apply to BGP connections:
```routeros
/routing/bgp/connection
set [find name~"sol"] input.filter=k8s-in
```

---

## Validation & Testing

### Traffic Path Verification

#### Internal Traffic (should use fc00:: and eth0/mesh)
```bash
# From K8s node, test Ceph access
ping6 fc00:20::1  # Should succeed, route via eth0
traceroute6 fc00:20::1  # Should show fc00:101::fffe anycast gateway

# Verify route
ip -6 route get fc00:20::1
# Expected: fc00:20::1 via fc00:101::fffe dev eth0 src fc00:101::11 metric 100

# Test actual Ceph connection
ceph -s --conf=/dev/null -m fc00:20::1,fc00:20::2,fc00:20::3 --keyring /etc/ceph/ceph.client.admin.keyring
```

#### External Traffic (should use fd00:: and eth1)
```bash
# From K8s node
ping6 fd00:10::1  # Should succeed, route via eth1
traceroute6 fd00:10::1  # Should show fd00:101::fffe gateway

# Verify route
ip -6 route get fd00:10::1
# Expected: fd00:10::1 via fd00:101::fffe dev eth1 src fd00:101::11
```

#### Pod Traffic (uses Cilium overlay, but mesh underlay)
```bash
# Deploy test pods
kubectl run test1 --image=nicolaka/netshoot --command -- sleep 3600
kubectl run test2 --image=nicolaka/netshoot --command -- sleep 3600

# Get pod IPs (should be fd00:101:44-49::/64 range)
kubectl get pods -o wide

# Test pod-to-pod (Cilium handles encap, uses fc00:101:: mesh)
kubectl exec test1 -- ping6 -c 2 <test2-ipv6>
```

### Bandwidth Testing

```bash
# Ceph storage (should use 10G mesh - eth0)
# From K8s node:
iperf3 -c fc00:20::1 -6 -t 10
# Expected: ~9+ Gbps (limited by single stream, not link)

# Internet egress (should use 1G uplink - eth1)
# From K8s node to internet server:
iperf3 -c <internet-iperf-server> -6 -t 10
# Expected: ~900 Mbps
```

### BGP Verification

```bash
# On K8s node (in FRR vtysh)
vtysh -c "show bgp ipv6 unicast summary"
vtysh -c "show bgp ipv6 unicast neighbors fd00:101::fffe advertised-routes"
vtysh -c "show isis neighbor"

# On RouterOS
/routing/bgp/session/print where remote.address~"fd00:255:101"
/ipv6/route/print where bgp
```

---

## Troubleshooting Guide

### Issue: Can't reach Ceph from K8s pods

**Check route from node:**
```bash
ip -6 route get fc00:20::1
# Should show: via fc00:101::fffe dev eth0
```

**Check anycast gateway:**
```bash
# From any PVE host
ip -6 addr show vnet101 | grep fc00:101::fffe
# Should show: inet6 fc00:101::fffe/64 scope global
```

**Check Proxmox SDN routing:**
```bash
# On pve01
ip -6 route show | grep fc00:20
# Should show routes to fc00:20::2 and fc00:20::3 via mesh links
```

**Test connectivity from pod:**
```bash
kubectl run ceph-test --image=quay.io/ceph/ceph:v18 --rm -it --restart=Never -- \
  ceph -s --conf=/dev/null -m fc00:20::1,fc00:20::2,fc00:20::3 --keyring=/dev/null
```

### Issue: LoadBalancer IPs not reachable

**Check Cilium BGP:**
```bash
cilium bgp peers
# Should show fd00:101::fffe as Established

cilium bgp routes advertised ipv6 unicast
# Should show fd00:101:cafe::/112
```

**Check RouterOS:**
```routeros
/routing/bgp/session/print where remote.address~"fd00:255:101"
# All sessions should show "established"

/ipv6/route/print where dst-address~"fd00:101:cafe"
# Should show BGP-learned routes
```

**Check static route to loopback:**
```routeros
/ipv6/route/print where dst-address=fd00:255:101::11/128
# Should show gateway=fd00:101::11
```

### Issue: Pod-to-pod slow or failing

**Check Cilium status:**
```bash
cilium status
# Look for "KubeProxyReplacement: Strict" and "Bandwidth Manager: EDT"

# Check datapath mode
kubectl -n kube-system get cm cilium-config -o yaml | grep -E "tunnel|routing-mode"
# Native routing is faster, VXLAN works but adds overhead
```

**Check IS-IS for loopback distribution:**
```bash
# On each node
vtysh -c "show isis neighbor"
# Should show other K8s nodes as neighbors

vtysh -c "show ipv6 route isis"
# Should show other nodes' pod CIDRs
```

---

## Future Considerations

### 1. Aligning Pod CIDR Semantics

**Current:** fd00:101:44::/60 (external semantics)
**Actual traffic:** Flows over fc00:101:: mesh (internal fast-ring)

**Option:** Migrate to fc00:101:10::/60 to align semantics with reality.

**Impact:** Requires pod recreation (all pods restart with new IPs).

**Benefit:** Makes addressing scheme more intuitive (fc00 = internal, fd00 = external).

### 2. LoadBalancer Pool Renaming

**Current:** fd00:101:cafe::/112 (mnemonic: "café" = public services)
**Alternative:** fd00:101:1b::/112 (semantic: "1b" = LoadBalancer)

**Impact:** Requires updating all LoadBalancer services.

**Benefit:** More explicit naming, scales to more pools (fd00:101:2b::, fd00:101:3b::, etc.).

### 3. Adding Storage Loopbacks

**Proposal:** Add fc00:255:101::X/128 loopbacks for Ceph CSI source binding.

**Purpose:** Ensures Ceph traffic originates from a stable, predictable IP.

**Implementation:**
1. Add loopback IPs: `ip -6 addr add fc00:255:101::X/128 dev lo`
2. Advertise via IS-IS on eth0
3. Configure Ceph CSI to bind to this IP when mounting

**Benefit:** Better troubleshooting, consistent source IPs for Ceph ACLs.

### 4. IPv4 Dual-Stack Alignment

Consider using the same semantic separation for IPv4:
- **10.20-21.0.0/16** - Internal (Ceph, mesh)
- **10.10.0.0/16** - Management
- **10.101.0.0/16** - K8s cluster 101 external
- **172.16.101.0/24** - K8s cluster 101 services

### 5. Expanded Cluster Support

For additional clusters, follow the same pattern:
- **fc00:102::/64** - Cluster 102 mesh (internal)
- **fd00:102::/64** - Cluster 102 egress (external)
- **fd00:255:102::/64** - Cluster 102 loopbacks + VIP

**Capacity:** Can support up to cluster 199 before needing renumbering.

---

## Complete IP Inventory

### Proxmox Hosts
| Host | Management | BGP Loopback | Ceph Public | Ceph Cluster |
|------|------------|--------------|-------------|--------------|
| pve01 | fd00:10::1 | fd00:0:0:ffff::1 | fc00:20::1 | fc00:21::1 |
| pve02 | fd00:10::2 | fd00:0:0:ffff::2 | fc00:20::2 | fc00:21::2 |
| pve03 | fd00:10::3 | fd00:0:0:ffff::3 | fc00:20::3 | fc00:21::3 |

### Kubernetes Nodes
| Host | Mesh (eth0) | Egress (eth1) | BGP Loopback | Pod CIDR |
|------|-------------|---------------|--------------|----------|
| solcp011 | fc00:101::11 | fd00:101::11 | fd00:255:101::11 | fd00:101:44::/64 |
| solcp012 | fc00:101::12 | fd00:101::12 | fd00:255:101::12 | fd00:101:45::/64 |
| solcp013 | fc00:101::13 | fd00:101::13 | fd00:255:101::13 | fd00:101:46::/64 |
| solwk021 | fc00:101::21 | fd00:101::21 | fd00:255:101::21 | fd00:101:47::/64 |
| solwk022 | fc00:101::22 | fd00:101::22 | fd00:255:101::22 | fd00:101:48::/64 |
| solwk023 | fc00:101::23 | fd00:101::23 | fd00:255:101::23 | fd00:101:49::/64 |

### Kubernetes Services
| Service Type | IPv6 Prefix | IPv4 Prefix | Purpose |
|--------------|-------------|-------------|---------|
| Pod CIDR | fd00:101:44::/60 | 10.244.0.0/16 | Pod IPs |
| ClusterIP | fd00:101:96::/108 | 10.96.0.0/12 | Internal services |
| LoadBalancer | fd00:101:cafe::/112 | - | External services |
| Control Plane VIP | fd00:255:101::ac/128 | - | K8s API endpoint |

### Key Infrastructure IPs
| IP | Purpose | Location |
|----|---------|----------|
| fc00:101::fffe | K8s mesh anycast gateway | All PVE hosts (vnet101) |
| fd00:101::fffe | K8s egress gateway | RouterOS (VLAN 101) |
| fd00:10::fffe | Management gateway | RouterOS (VLAN 10) |
| fd00:0:0:ffff::fffe | PVE BGP peer | RouterOS loopback |
| fd00:255:101::ac | K8s control plane VIP | solcp01X (health-checked) |

---

## References

- **RFC 4193:** Unique Local IPv6 Unicast Addresses
- **Proxmox SDN Documentation:** https://pve.proxmox.com/wiki/Software-Defined_Network
- **Cilium BGP:** https://docs.cilium.io/en/stable/network/bgp-control-plane/
- **FRR Documentation:** https://docs.frrouting.org/
- **IS-IS for IP Internets:** RFC 1195

---

**End of Document**
