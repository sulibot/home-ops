# FRR BGP Architecture and Configuration Specification
**Multi-Tenant EVPN/VXLAN Datacenter with VM/Kubernetes Workload Routing**

**Author:** Network Engineering
**Audience:** Network Engineers, Platform Infrastructure
**Purpose:** Define FRR BGP requirements and implementation for both infrastructure (Proxmox VE) and tenant workloads (VMs/Talos nodes)

**Version:** 2.0
**Last Updated:** 2026-01-03

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Control Plane Design](#3-control-plane-design)
4. [Infrastructure Layer: Proxmox VE FRR](#4-infrastructure-layer-proxmox-ve-frr)
5. [Tenant Layer: VM/Talos Bird2](#5-tenant-layer-vmtalos-bird2)
6. [BGP Peering Architecture](#6-bgp-peering-architecture)
7. [Route Advertisement and Filtering](#7-route-advertisement-and-filtering)
8. [Implementation Guide](#8-implementation-guide)
9. [Traffic Flows and Forwarding Behavior](#9-traffic-flows-and-forwarding-behavior)
10. [Failure Scenarios and Recovery](#10-failure-scenarios-and-recovery)
11. [Operational Procedures](#11-operational-procedures)

---

## 1. Executive Summary

### 1.1 What Problem Does This Solve?

**Primary Objectives:**
1. Provide Layer 3 routing between tenant workloads (VMs/Kubernetes pods) and external networks
2. Enable VM mobility without renumbering
3. Distribute default route to workloads while importing workload routes to infrastructure
4. Integrate Kubernetes pod networks into the datacenter routing fabric

**Key Design Decisions:**
- **Infrastructure routing:** OSPF + iBGP + EVPN for underlay and overlay control plane
- **Tenant routing:** eBGP peering between VMs and local hypervisor
- **Anycast gateway:** Shared Layer 3 gateway address across all hypervisors in VRF
- **Route exchange:** Bidirectional - VMs advertise loopbacks/pod networks, receive default routes

### 1.2 Technology Stack

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| Infrastructure Routing | FRR | 10.5.0 | OSPF, BGP, EVPN control plane |
| Overlay Network | EVPN/VXLAN | - | Layer 2 extension across hypervisors |
| VM/Talos Routing | FRR | 10.5.0 | BGP client for workload routing |
| Kubernetes CNI | Cilium | 1.16+ | Pod networking with BGP integration |
| VRF Isolation | Linux VRF | - | Tenant network isolation |

### 1.3 Key Architectural Constraints

**Requirements:**
- ✅ Dual-stack IPv4/IPv6 with symmetric behavior
- ✅ No NAT - all addressing is routed end-to-end
- ✅ VM mobility without renumbering (loopback follows VM)
- ✅ Scalable to 100+ VMs per tenant VRF
- ✅ Zero-touch VM onboarding (dynamic BGP neighbors)

**Non-Requirements:**
- ❌ BGP-based load balancing (handled by Cilium/ECMP)
- ❌ Full internet table import (default route only)
- ❌ Multi-path export to edge (single best path)

---

## 2. Architecture Overview

### 2.1 Network Topology

```
                    ┌─────────────────────────────────────┐
                    │  Edge Router (MikroTik RouterOS)   │
                    │  AS 4200000000                      │
                    │  10.255.0.254 / fd00:0:0:ffff::fffe│
                    └───────────────┬─────────────────────┘
                                    │ eBGP
                    ┌───────────────┴─────────────────────┐
                    │  Proxmox VE Cluster (iBGP Mesh)    │
                    │  AS 4200001000                      │
                    │                                     │
                    │  ┌──────────┬──────────┬──────────┐│
                    │  │  pve01   │  pve02   │  pve03   ││
                    │  │ .0.1/::1 │ .0.2/::2 │ .0.3/::3 ││
                    │  └─────┬────┴────┬─────┴────┬─────┘│
                    │        │ OSPF+   │ OSPF+    │      │
                    │        │ iBGP    │ iBGP     │      │
                    │        │ EVPN    │ EVPN     │      │
                    └────────┼─────────┼──────────┼──────┘
                             │         │          │
                    ┌────────┴─────────┴──────────┴──────┐
                    │  Tenant VRF (vrf_evpnz1)           │
                    │  EVPN VNI 10101 / VXLAN            │
                    │  Anycast GW: .254 / ::fffe         │
                    └─────────────┬──────────────────────┘
                                  │ Dynamic eBGP
                    ┌─────────────┴──────────────────────┐
                    │   Tenant Workloads (per-VM ASN)    │
                    │                                    │
                    │  ┌──────────┬──────────┬─────────┐│
                    │  │ Talos CP │ Talos WK │ Test VM ││
                    │  │ AS 42101 │ AS 42101 │ AS 4200 ││
                    │  │   01011  │   01021  │ 101006  ││
                    │  └──────────┴──────────┴─────────┘│
                    └────────────────────────────────────┘
```

### 2.2 Routing Domain Hierarchy

**Three-Tier Routing Model:**

1. **Global Default Table (Infrastructure)**
   - OSPF for underlay reachability (loopback-to-loopback)
   - iBGP for infrastructure route exchange
   - eBGP to edge router for internet connectivity
   - EVPN for VXLAN overlay signaling

2. **Tenant VRF (vrf_evpnz1)**
   - BGP listen ranges for dynamic VM peering
   - Route leaking from/to global table
   - Per-tenant network isolation
   - Anycast gateway for first-hop routing

3. **VM/Workload Layer**
   - BGP client peering with local hypervisor
   - Advertises loopback + pod networks
   - Imports default route only
   - No IGP - pure BGP routing

### 2.3 ASN Allocation Strategy

| Entity | ASN Range | Example | Type |
|--------|-----------|---------|------|
| Infrastructure | `4200001000` | PVE cluster | iBGP |
| Edge Router | `4200000000` | MikroTik | eBGP |
| Test VMs | `4200100000-4200199999` | debian-test-1 = `4200101006` | eBGP |
| Talos Control Planes | `4210101011-4210101019` | solcp01 = `4210101011` | eBGP |
| Talos Workers | `4210101021-4210101099` | solwk01 = `4210101021` | eBGP |

**ASN Pattern for Talos Nodes:**
```
Format: 421<cluster_id><node_type><node_suffix>

Where:
  cluster_id   = 0101 (for tenant 101)
  node_type    = 01 (control plane) or 02 (worker)
  node_suffix  = 11-19 (CP) or 21-99 (worker)

Examples:
  solcp01: 4210101011 (cluster 0101, CP, node 11)
  solwk02: 4210101022 (cluster 0101, worker, node 22)
```

**Design Rationale:**
- Unique ASN per VM enables `remote-as external` without manual configuration
- ASN encodes role and identity for troubleshooting
- Prevents iBGP split-brain scenarios
- Scales to 1000s of workloads

---

## 3. Control Plane Design

### 3.1 Routing Protocol Separation of Concerns

**OSPF (Infrastructure Underlay):**
- **Purpose:** Provide IP reachability for control plane communications
- **Scope:** Infrastructure loopbacks only (`10.255.0.0/16`, `fd00:0:0:ffff::/64`)
- **Topology:** Area 0.0.0.0 (backbone)
- **Interfaces:** Physical mesh links, management segment
- **NOT advertised:** Tenant networks, VM loopbacks, workload prefixes

**iBGP (Infrastructure Overlay):**
- **Purpose:** Exchange infrastructure routes and aggregate tenant routes
- **Scope:** Global default table
- **Topology:** Full mesh between pve01, pve02, pve03
- **Peering:** IPv6 loopback-to-loopback (`fd00:0:0:ffff::1-3`)
- **Advertisements:** Infrastructure connected routes, aggregated tenant prefixes

**EVPN (Layer 2 Overlay Signaling):**
- **Purpose:** Distribute MAC/IP bindings for VXLAN overlay
- **Address Family:** `l2vpn evpn`
- **VNI Assignment:** VNI 10101 for tenant 101
- **Neighbor Suppression:** Enabled (PVE bridge responds to ARP/ND locally)
- **MAC Learning:** Control-plane only (no data-plane learning)

**eBGP (Tenant Workload Peering):**
- **Purpose:** Exchange routes between VMs and infrastructure
- **Scope:** Tenant VRF only
- **Topology:** Each VM peers with local hypervisor anycast gateway
- **Peering:** IPv6 ULA addresses
- **Advertisements:** VM→PVE (loopbacks, pod networks), PVE→VM (default routes)

### 3.2 Route Leaking and VRF Integration

**Problem Statement:**
- Tenant routes must be exported to global table (for edge router advertisement)
- Global default route must be imported to tenant VRF (for VM consumption)
- No route leakage between different tenant VRFs

**FRR Solution: `import vrf` Directive**

```
# In global table BGP config
router bgp 4200001000
  address-family ipv6 unicast
    import vrf vrf_evpnz1    # Import tenant routes to global table
  exit-address-family

# In VRF BGP config
router bgp 4200001000 vrf vrf_evpnz1
  address-family ipv6 unicast
    import vrf default       # Import global routes (incl. default) to VRF
  exit-address-family
```

**Traffic Flow:**
1. VM advertises loopback to VRF BGP table
2. VRF route is imported to global table via `import vrf`
3. Global BGP advertises to edge router (filtered by prefix-list)
4. Edge router sends default route to global BGP
5. Default route is imported to VRF via `import vrf default`
6. VRF BGP advertises default to VM

**Route Filtering:**
- Export to edge: Only tenant loopbacks, pod networks, GUA prefixes
- Import from edge: Any routes (typically default + specific routes)
- Export to VMs: Default routes + peer loopbacks
- Import from VMs: Loopbacks and pod CIDRs (filtered by prefix-list)

---

## 4. Infrastructure Layer: Proxmox VE FRR

### 4.1 FRR Services and Daemons

**Enabled Daemons:**
```
zebra=yes           # Kernel routing table manager
bgpd=yes            # BGP routing daemon
ospfd=yes           # OSPFv2 daemon
ospf6d=yes          # OSPFv3 daemon
staticd=no          # Not needed (dynamic routing only)
isisd=no            # Not using IS-IS
```

**Daemon Startup Order:**
1. `zebra` - Must start first (manages kernel FIB)
2. `ospfd` + `ospf6d` - Establish underlay reachability
3. `bgpd` - BGP sessions establish after OSPF convergence

### 4.2 OSPF Configuration

**Purpose:** Advertise infrastructure loopback addresses only

**IPv4 OSPF:**
```
router ospf
  ospf router-id 10.255.0.<PVE_ID>
  redistribute kernel route-map OSPF_INFRA_V4
  passive-interface default
  no passive-interface <mesh-links>
  no passive-interface vmbr0.10

ip prefix-list OSPF_INFRA_V4 seq 5 permit 10.255.0.0/16 le 32
ip prefix-list OSPF_INFRA_V4 seq 10 deny 0.0.0.0/0 le 32

route-map OSPF_INFRA_V4 permit 10
  match ip address prefix-list OSPF_INFRA_V4
```

**IPv6 OSPF:**
```
router ospf6
  ospf6 router-id 10.255.0.<PVE_ID>
  redistribute connected route-map OSPF_INFRA_V6

ipv6 prefix-list OSPF_INFRA_V6 seq 5 permit fd00:0:0:ffff::/64 le 128
ipv6 prefix-list OSPF_INFRA_V6 seq 10 deny ::/0 le 128

route-map OSPF_INFRA_V6 permit 10
  match ipv6 address prefix-list OSPF_INFRA_V6
```

**Key Design Points:**
- Router-ID is infrastructure loopback IPv4 (always /32)
- Passive by default - only enable on mesh links
- Redistribute kernel routes (loopbacks configured outside FRR)
- Strict filtering prevents tenant leakage

### 4.3 OSPF Interface Configuration

**Purpose:** Enable OSPF on underlay interfaces for infrastructure reachability

**Loopback Interface (Infrastructure Loopback):**
```
interface dummy_underlay
  ip ospf area 0.0.0.0
  ip ospf network broadcast
  ip ospf passive
  ipv6 ospf6 area 0.0.0.0
  ipv6 ospf6 network point-to-point
exit
```

**Physical Mesh Links (Point-to-Point):**
```
# Example: pve01 to pve02 link
interface vmbr1v20
  ip ospf area 0.0.0.0
  ip ospf cost 10
  ip ospf network point-to-point
  ipv6 ospf6 area 0.0.0.0
  ipv6 ospf6 cost 10
  ipv6 ospf6 network point-to-point
exit

# Example: pve01 to pve03 link
interface vmbr1v21
  ip ospf area 0.0.0.0
  ip ospf cost 10
  ip ospf network point-to-point
  ipv6 ospf6 area 0.0.0.0
  ipv6 ospf6 cost 10
  ipv6 ospf6 network point-to-point
exit
```

**Management Segment (Broadcast for RouterOS Peering):**
```
interface vmbr0.10
  ip ospf area 0.0.0.0
  ip ospf cost 1000              # High cost - backup path only
  ipv6 ospf6 area 0.0.0.0
  ipv6 ospf6 cost 1000
exit
```

**Key Configuration Points:**
- **Area 0.0.0.0:** All interfaces in OSPF backbone area
- **Network Type:**
  - `point-to-point`: Mesh links (no DR/BDR election, faster convergence)
  - `broadcast`: Management segment (supports multiple routers)
- **Cost Tuning:**
  - Mesh links: Cost 10 (preferred path)
  - Management: Cost 1000 (backup only, avoids hairpinning via edge router)
- **Passive Interfaces:**
  - Global: `passive-interface default` (no OSPF Hello on unconfigured interfaces)
  - Per-interface: `no passive-interface <iface>` overrides for mesh links
  - Prevents OSPF adjacencies on tenant VRF interfaces

**OSPF Interface Selection Strategy:**
```
# In router ospf config
passive-interface default          # All interfaces passive by default
no passive-interface vmbr1v20      # Enable on mesh link
no passive-interface vmbr1v21      # Enable on mesh link
no passive-interface vmbr0.10      # Enable on mgmt segment
no passive-interface dummy_underlay # Enable on loopback dummy
```

**Why Use Dummy Interface for Loopback:**
- Linux loopback (lo) is special - cannot be added to OSPF easily
- Dummy interface provides stable IP anchor for router-ID
- Configured in `/etc/network/interfaces`:
```
auto dummy_underlay
iface dummy_underlay inet static
    address 10.255.0.1/32
    pre-up ip link add dummy_underlay type dummy

iface dummy_underlay inet6 static
    address fd00:0:0:ffff::1/128
```

### 4.4 Global BGP Configuration

**iBGP Mesh for Infrastructure:**
```
router bgp 4200001000
  bgp router-id 10.255.0.<PVE_ID>
  no bgp default ipv4-unicast    # Explicit address-family activation
  no bgp network import-check    # Allow advertising routes from other protocols
  timers bgp 10 30               # Keepalive 10s, holdtime 30s

  # iBGP neighbors (example for pve01)
  neighbor fd00:0:0:ffff::2 remote-as 4200001000
  neighbor fd00:0:0:ffff::2 description "iBGP to pve02 loopback"
  neighbor fd00:0:0:ffff::2 update-source fd00:0:0:ffff::1

  neighbor fd00:0:0:ffff::3 remote-as 4200001000
  neighbor fd00:0:0:ffff::3 description "iBGP to pve03 loopback"
  neighbor fd00:0:0:ffff::3 update-source fd00:0:0:ffff::1

  # Edge eBGP
  neighbor fd00:0:0:ffff::fffe remote-as 4200000000
  neighbor fd00:0:0:ffff::fffe description "MikroTik edge router"
  neighbor fd00:0:0:ffff::fffe update-source fd00:0:0:ffff::<PVE_ID>
  neighbor fd00:0:0:ffff::fffe ebgp-multihop 5
```

**IPv6 Unicast Address Family:**
```
  address-family ipv6 unicast
    # Advertise infrastructure connected routes
    redistribute connected route-map EXPORT_V6_CONNECTED

    # Import tenant routes from VRF
    import vrf vrf_evpnz1

    # Edge router peering
    neighbor fd00:0:0:ffff::fffe activate
    neighbor fd00:0:0:ffff::fffe route-map IMPORT_FROM_ROUTEROS in
    neighbor fd00:0:0:ffff::fffe route-map EXPORT_TO_ROUTEROS out
    neighbor fd00:0:0:ffff::fffe next-hop-self force

    # iBGP neighbors
    neighbor fd00:0:0:ffff::2 activate
    neighbor fd00:0:0:ffff::3 activate

    # ECMP support
    maximum-paths 4
    maximum-paths ibgp 4
  exit-address-family
```

**IPv4 Unicast Address Family:**
```
  address-family ipv4 unicast
    redistribute connected route-map EXPORT_V4_CONNECTED
    import vrf vrf_evpnz1

    neighbor 10.255.0.254 activate
    neighbor 10.255.0.254 route-map IMPORT_FROM_ROUTEROS in
    neighbor 10.255.0.254 route-map EXPORT_TO_ROUTEROS out
    neighbor 10.255.0.254 next-hop-self

    maximum-paths 4
    maximum-paths ibgp 4
  exit-address-family
```

**EVPN Address Family:**
```
  address-family l2vpn evpn
    neighbor fd00:0:0:ffff::2 activate
    neighbor fd00:0:0:ffff::3 activate
    advertise-all-vni        # Advertise all local VNIs
    advertise-svi-ip         # Advertise SVI addresses
  exit-address-family
```

### 4.4 VRF BGP Configuration (Tenant Routing)

**Purpose:** Peer with tenant VMs dynamically, exchange routes with global table

```
router bgp 4200001000 vrf vrf_evpnz1
  bgp router-id 10.255.0.<PVE_ID>
  no bgp default ipv4-unicast
  bgp listen limit 100          # Support up to 100 dynamic neighbors

  # Peer-group for VMs
  neighbor VMS peer-group
  neighbor VMS remote-as external          # Each VM has unique ASN
  neighbor VMS capability extended-nexthop # IPv6 next-hop for IPv4 routes

  # Dynamic neighbor ranges (BGP listen)
  bgp listen range fd00:101::/64 peer-group VMS      # Tenant data plane
  bgp listen range fd00:101:fe::/64 peer-group VMS   # Tenant loopbacks
```

**Address Family Configuration:**
```
  address-family ipv4 unicast
    neighbor VMS activate
    neighbor VMS route-map IMPORT-VM-ROUTES in       # Filter VM advertisements
    neighbor VMS route-map EXPORT_TO_TALOS out       # Send defaults + loopbacks
    redistribute connected route-map VRF_CONNECTED_V4  # Advertise VRF subnets
    import vrf default                               # Import global default route
  exit-address-family

  address-family ipv6 unicast
    neighbor VMS activate
    neighbor VMS route-map IMPORT-VM-ROUTES in
    neighbor VMS route-map EXPORT_TO_TALOS out
    redistribute connected route-map VRF_CONNECTED_V6
    import vrf default
  exit-address-family
```

**BGP Listen Range Behavior:**
- VM initiates BGP connection to anycast gateway `fd00:101::fffe`
- PVE accepts connection if source IP matches listen range
- Session established with peer-group defaults (`remote-as external`)
- VM's unique ASN automatically recognized (no manual neighbor config)

### 4.5 Route Filtering - Export to Edge Router

**Requirement:** Only advertise tenant routes (never infrastructure) to edge

**IPv6 Tenant Routes:**
```
# Tenant ULA subnets (fd00:101::/64, fd00:102::/64, etc)
ipv6 prefix-list TENANT_ONLY_V6 seq 5 permit fd00:101::/64 le 128
ipv6 prefix-list TENANT_ONLY_V6 seq 10 permit fd00:102::/64 le 128

# Tenant GUA prefixes (if delegated)
ipv6 prefix-list TENANT_ONLY_V6 seq 15 permit 2600:xxxx::/64 le 128

# VM loopback ranges (new pattern: fd00:101:fe::/64 as /128)
ipv6 prefix-list TENANT_ONLY_V6 seq 20 permit fd00:101:fe::/64 ge 128 le 128

# DENY infrastructure ranges
ipv6 prefix-list TENANT_ONLY_V6 seq 90 deny fd00:0:0:ffff::/48 le 128
ipv6 prefix-list TENANT_ONLY_V6 seq 95 deny fd00:10::/64 le 128
ipv6 prefix-list TENANT_ONLY_V6 seq 99 deny ::/0 le 128

route-map EXPORT_TO_ROUTEROS permit 10
  match ipv6 address prefix-list TENANT_ONLY_V6
  set ipv6 next-hop global fd00:0:0:ffff::<PVE_ID>  # Set self as next-hop
```

**IPv4 Tenant Routes:**
```
# Tenant subnets (10.101.0.0/24, etc)
ip prefix-list TENANT_ONLY_V4 seq 5 permit 10.101.0.0/24

# VM loopback ranges (new pattern: 10.101.254.0/24 as /32)
ip prefix-list TENANT_ONLY_V4 seq 10 permit 10.101.254.0/24 ge 32 le 32

# DENY infrastructure loopbacks
ip prefix-list TENANT_ONLY_V4 seq 90 deny 10.255.0.0/24 ge 32
ip prefix-list TENANT_ONLY_V4 seq 99 deny 0.0.0.0/0 le 32

route-map EXPORT_TO_ROUTEROS permit 10
  match ip address prefix-list TENANT_ONLY_V4
  set ip next-hop 10.255.0.<PVE_ID>
```

### 4.6 Route Filtering - Import from VMs

**Requirement:** Accept only VM loopbacks and pod networks (never infrastructure or bogons)

```
# VM loopback addresses (10.101.254.0/24 as /32 hosts)
ip prefix-list VM-LOOPBACKS-V4 seq 5 permit 10.101.254.0/24 ge 32 le 32

# Kubernetes pod CIDRs (10.101.244.0/22)
ip prefix-list VM-K8S-PODS-V4 seq 5 permit 10.101.244.0/22 le 24

# VM loopback addresses (fd00:101:fe::/64 as /128 hosts)
ipv6 prefix-list VM-LOOPBACKS-V6 seq 5 permit fd00:101:fe::/64 ge 128 le 128

# Kubernetes pod CIDRs (fd00:101:244::/60)
ipv6 prefix-list VM-K8S-PODS-V6 seq 5 permit fd00:101:244::/60 le 64

route-map IMPORT-VM-ROUTES permit 10
  match ip address prefix-list VM-LOOPBACKS-V4
route-map IMPORT-VM-ROUTES permit 20
  match ip address prefix-list VM-K8S-PODS-V4
route-map IMPORT-VM-ROUTES permit 30
  match ipv6 address prefix-list VM-LOOPBACKS-V6
route-map IMPORT-VM-ROUTES permit 40
  match ipv6 address prefix-list VM-K8S-PODS-V6
route-map IMPORT-VM-ROUTES deny 99
```

**Critical Security Note:**
- Implicit deny-all at end (seq 99) prevents route injection attacks
- VMs cannot advertise infrastructure space back to PVE
- Prevents route table pollution from misconfigured VMs

### 4.7 Route Filtering - Export to VMs

**Requirement:** Send only default routes and peer loopbacks to VMs

```
# Default routes only
ip prefix-list DEFAULT_V4 seq 5 permit 0.0.0.0/0
ipv6 prefix-list DEFAULT_V6 seq 5 permit ::/0

# Allow VM to learn about peer loopbacks (for K8s node-to-node traffic)
ip prefix-list TALOS_LOOPBACKS seq 5 permit 10.101.254.0/24 ge 32
ipv6 prefix-list TALOS_LOOPBACKS_V6 seq 5 permit fd00:101:fe::/64 ge 128

route-map EXPORT_TO_TALOS permit 10
  match ip address prefix-list DEFAULT_V4
route-map EXPORT_TO_TALOS permit 20
  match ipv6 address prefix-list DEFAULT_V6
route-map EXPORT_TO_TALOS permit 30
  match ip address prefix-list TALOS_LOOPBACKS
route-map EXPORT_TO_TALOS permit 40
  match ipv6 address prefix-list TALOS_LOOPBACKS_V6
```

**Why Export Peer Loopbacks:**
- Kubernetes nodes need to reach each other's loopbacks directly
- Enables Talos/etcd clustering over loopback addresses
- Avoids hairpinning through anycast gateway for node-to-node traffic

---

## 5. Tenant Layer: VM/Talos Bird2

### 5.1 VM Routing Requirements

**Design Goals:**
1. Advertise VM loopback address to infrastructure
2. Import default route from infrastructure
3. No full routing table - default route only
4. No IGP - pure BGP client
5. Automatically establish BGP on VM first boot

**Daemon:** Bird2 (via Talos System Extension)

### 5.2 Talos Extension Architecture

**Deployment Method:**
- Talos System Extension (runs as privileged container)
- Mount configuration from host filesystem
- Network namespace: host (shares node network)

**Container Mounts:**
```yaml
container:
  mounts:
    - source: /var/etc/bird          # Host path
      destination: /usr/local/etc    # Container path
      type: bind
      options: [bind, rw]
```

**Configuration Injection:**
- Talos `ExtensionServiceConfig` writes `/var/lib/frr/frr.conf`
- FRR container reads config from `/etc/frr/frr.conf` (bind mount)
- Changes require Talos machine config update + node reboot

### 5.3 VM BGP Configuration

**BGP Daemon Configuration:**
```
frr version 10.2
frr defaults datacenter
hostname <node-name>
log syslog informational
service integrated-vtysh-config

router bgp <local_asn>
  bgp router-id <loopback_ipv4>          # e.g., 10.255.101.11
  no bgp default ipv4-unicast            # Explicit AF activation
  no bgp default ipv6-unicast
  bgp graceful-restart                   # Enable GR for maintenance
  timers bgp 10 30                       # Fast convergence
```

**Neighbor Configuration:**
```
  # Peer with PVE anycast gateway
  neighbor fd00:101::fffe remote-as 4200001000
  neighbor fd00:101::fffe update-source fd00:101::11  # CRITICAL: Use primary IP
  neighbor fd00:101::fffe description "PVE ULA Anycast Gateway"
  neighbor fd00:101::fffe capability extended-nexthop # IPv6 NH for IPv4
```

**Why `update-source` is Critical:**
- Without it, FRR auto-selects source IP based on routing table
- If VM has VIP configured (e.g., Kubernetes control plane VIP), FRR prefers /128 over /64
- Multiple VMs using same VIP as source → only one BGP session establishes
- **Solution:** Explicitly set source to primary ens18 IP address

**Address Family Configuration:**
```
  address-family ipv4 unicast
    redistribute connected route-map ADVERTISE-LOOPBACKS  # Send loopback
    neighbor fd00:101::fffe activate
    neighbor fd00:101::fffe route-map IMPORT-DEFAULT-v4 in   # Accept default only
    neighbor fd00:101::fffe route-map ADVERTISE-LOOPBACKS out
  exit-address-family

  address-family ipv6 unicast
    redistribute connected route-map ADVERTISE-LOOPBACKS-V6
    neighbor fd00:101::fffe activate
    neighbor fd00:101::fffe route-map IMPORT-DEFAULT-v6 in
    neighbor fd00:101::fffe route-map ADVERTISE-LOOPBACKS-V6 out
  exit-address-family
```

### 5.4 VM Route Filtering

**Import Filter - Accept Default Route Only:**
```
# IPv6
ipv6 prefix-list DEFAULT-ONLY-v6 seq 10 permit ::/0
route-map IMPORT-DEFAULT-v6 permit 10
  match ipv6 address prefix-list DEFAULT-ONLY-v6
route-map IMPORT-DEFAULT-v6 deny 90

# IPv4
ip prefix-list DEFAULT-ONLY-v4 seq 10 permit 0.0.0.0/0
route-map IMPORT-DEFAULT-v4 permit 10
  match ip address prefix-list DEFAULT-ONLY-v4
route-map IMPORT-DEFAULT-v4 deny 90
```

**Export Filter - Advertise Loopbacks Only:**
```
# IPv4 loopback (10.101.254.0/24 as /32 hosts)
ip prefix-list LOOPBACKS seq 10 permit 10.101.254.0/24 ge 32
route-map ADVERTISE-LOOPBACKS permit 10
  match ip address prefix-list LOOPBACKS

# IPv6 loopback (fd00:101:fe::/64 as /128 hosts)
ipv6 prefix-list LOOPBACKS-V6 seq 10 permit fd00:101:fe::/64 ge 128
route-map ADVERTISE-LOOPBACKS-V6 permit 10
  match ipv6 address prefix-list LOOPBACKS-V6
```

**Design Notes:**
- `ge 32` / `ge 128` ensures only host routes are advertised (not subnets)
- Connected redistribution picks up loopback interfaces automatically
- No manual network statements required

### 5.5 Kubernetes Pod Network Advertisement (Cilium Integration)

**Current State:** FRR on Talos nodes only advertises loopbacks

**Future Enhancement:** Cilium BGP Control Plane
```yaml
# Cilium BGP configuration (not yet implemented)
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: bgp-peering-policy
spec:
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/control-plane: ""
  virtualRouters:
  - localASN: 4210101011  # Matches FRR local ASN
    neighbors:
    - peerAddress: fd00:101::fffe
      peerASN: 4200001000
    serviceSelector:
      matchLabels:
        advertise: bgp
    podCIDRSelector:
      matchExpressions:
      - key: advertise
        operator: Exists
```

**How It Works:**
1. Cilium detects pod CIDR assignments per node
2. Advertises pod subnets via BGP to local gateway
3. PVE imports pod routes, redistributes to global table
4. Edge router learns pod networks, provides return path

**Current Workaround:**
- Pods use node IP as source (SNAT)
- Node loopback is already advertised
- Direct pod-to-pod traffic works (Cilium overlay)

---

## 6. BGP Peering Architecture

### 6.1 Peering Topology

**Infrastructure iBGP Mesh:**
```
pve01 (fd00:0:0:ffff::1) ←→ pve02 (fd00:0:0:ffff::2)
pve01 (fd00:0:0:ffff::1) ←→ pve03 (fd00:0:0:ffff::3)
pve02 (fd00:0:0:ffff::2) ←→ pve03 (fd00:0:0:ffff::3)
```
- Full mesh (N×(N-1)/2 sessions for N nodes)
- Loopback-to-loopback peering
- Same AS (4200001000)

**Infrastructure to Edge eBGP:**
```
pve01/02/03 (fd00:0:0:ffff::1-3) → edge (fd00:0:0:ffff::fffe)
```
- Multihop eBGP (TTL > 1 required)
- All PVE nodes peer with same edge router
- Different AS (PVE: 4200001000, Edge: 4200000000)

**Tenant VM to Infrastructure eBGP:**
```
VM (fd00:101::11) → Anycast GW (fd00:101::fffe) → Local PVE
```
- Single-hop eBGP (VMs are directly connected)
- Dynamic neighbor via BGP listen range
- Each VM has unique AS

### 6.2 Anycast Gateway Behavior

**Problem:** Multiple PVE hosts have same gateway IP `fd00:101::fffe`

**How VMs Reach Correct Host:**
1. VM sends BGP packet to `fd00:101::fffe` (anycast address)
2. EVPN neighbor suppression: Local PVE bridge responds to ND
3. Packet forwarded directly to local PVE (no VXLAN)
4. BGP session established with hypervisor hosting the VM

**Why This Works:**
- VMs always on a specific PVE host (not floating)
- EVPN learns VM MAC→PVE mapping
- Anycast gateway resolves to local PVE via layer 2

**Failure Mode:**
- If VM migrates to different PVE host during BGP session
- Session breaks (source IP changes to different anycast instance)
- VM re-establishes BGP with new local PVE
- Routes converge within 30s (hold timer)

### 6.3 BGP Session Parameters

**Timers:**
```
timers bgp 10 30
# Keepalive: 10 seconds
# Hold time: 30 seconds
# Detection time: 30 seconds (3 missed keepalives)
```

**Graceful Restart:**
```
bgp graceful-restart
# Allows BGP session to survive FRR daemon restart
# Preserves forwarding during control plane maintenance
```

**TCP MD5 Authentication:**
- Not currently implemented
- Future enhancement for production environments
- Would require key distribution via Talos machine config

### 6.4 Next-Hop Behavior

**iBGP Next-Hop Preservation:**
```
# By default, iBGP does NOT change next-hop
# For routes from VRF, next-hop is PVE loopback (e.g., fd00:0:0:ffff::1)

# Edge router peering - force next-hop to self
neighbor fd00:0:0:ffff::fffe next-hop-self force
```

**eBGP Next-Hop Rewrite:**
```
# eBGP automatically rewrites next-hop to self
# VM receives routes with next-hop = fd00:101::fffe (anycast gateway)
```

**Why `next-hop-self force` is Required:**
- Without it, edge router receives VM routes with next-hop = VM IP
- Edge router has no route to VM IPs (they're in VRF)
- Traffic black-holes
- **Solution:** PVE rewrites next-hop to its own loopback

---

## 7. Route Advertisement and Filtering

### 7.1 Route Flow Summary

**VM → PVE VRF:**
- VM advertises: Loopback (/32, /128)
- PVE accepts: Loopbacks, pod CIDRs (filtered by `IMPORT-VM-ROUTES`)

**PVE VRF → PVE Global:**
- Automatic via `import vrf vrf_evpnz1`
- All accepted VM routes imported

**PVE Global → Edge Router:**
- PVE advertises: Tenant loopbacks, pod CIDRs (filtered by `EXPORT_TO_ROUTEROS`)
- Edge accepts: All routes (no inbound filter)

**Edge Router → PVE Global:**
- Edge advertises: Default route (0.0.0.0/0, ::/0)
- PVE accepts: All routes (filtered by `IMPORT_FROM_ROUTEROS`)

**PVE Global → PVE VRF:**
- Automatic via `import vrf default` in VRF config
- Default route + infrastructure loopbacks imported

**PVE VRF → VM:**
- PVE advertises: Default route, peer loopbacks (filtered by `EXPORT_TO_TALOS`)
- VM accepts: Default route only (filtered by `IMPORT-DEFAULT-v4/v6`)

### 7.2 Redistribution Methods

**Connected Routes:**
```
redistribute connected route-map <filter>
```
- Used for: VRF subnet advertisements, VM loopback advertisements
- Picks up any interface in UP state
- Requires route-map filter to prevent leakage

**OSPF Routes:**
```
redistribute kernel route-map OSPF_INFRA_V4
```
- Used in OSPF to advertise loopbacks (configured via kernel)
- Not used in BGP (loopbacks learned via OSPF, not redistributed)

**VRF Import:**
```
import vrf <vrf-name>
```
- Bidirectional route leaking between VRFs
- Preserves attributes (AS path, next-hop)
- More efficient than redistribution

### 7.3 Prefix-List Design Patterns

**Exact Match:**
```
ip prefix-list DEFAULT seq 5 permit 0.0.0.0/0
# Matches only 0.0.0.0/0, no other prefixes
```

**Range Match:**
```
ip prefix-list LOOPBACKS seq 10 permit 10.101.254.0/24 ge 32 le 32
# Matches any /32 within 10.101.254.0/24
# ge = greater-or-equal, le = less-or-equal
```

**Subnet and Subnets:**
```
ipv6 prefix-list TENANT seq 5 permit fd00:101::/64 le 128
# Matches fd00:101::/64 and any more-specific route
```

**Deny-All Pattern:**
```
ip prefix-list FILTER seq 99 deny 0.0.0.0/0 le 32
# Explicit deny-all (matches any IPv4 prefix)
# Critical for security (prevents leakage)
```

### 7.4 BGP Large Community Implementation

**Configuration:**
```bash
! Define Large Community Lists
bgp large-community-list standard CL_K8S_INTERNAL permit 4200001000:0:100
bgp large-community-list standard CL_K8S_PUBLIC   permit 4200001000:0:200

! Match in Route Maps
route-map RM_EDGE_EXPORT_V6 permit 20
 match large-community CL_K8S_PUBLIC

! Set in Route Maps (Ingress Classification)
route-map RM_VMS_IN_V6 permit 10
 match ipv6 address prefix-list PL_K8S_PODS_V6
 set large-community 4200001000:0:100
```

---

## 8. Implementation Guide

### 8.1 Proxmox VE FRR Installation

**Install FRR Package:**
```bash
apt update
apt install frr frr-pythontools -y
```

**Enable Daemons:**
```bash
# Edit /etc/frr/daemons
zebra=yes
bgpd=yes
ospfd=yes
ospf6d=yes
staticd=no
```

**Start Services:**
```bash
systemctl enable frr.service
systemctl start frr.service
systemctl status frr.service
```

**Verify Daemons:**
```bash
vtysh -c "show daemons"
```

### 8.2 Proxmox VE Configuration Deployment

**Using Ansible (Recommended):**
```bash
cd /Users/sulibot/repos/github/home-ops/ansible/lae.proxmox

# Deploy to all PVE hosts
ansible-playbook -i inventory/hosts.ini playbooks/configure-frr.yml

# Deploy to single host
ansible-playbook -i inventory/hosts.ini playbooks/configure-frr.yml -l pve01
```

**Ansible Role Structure:**
```
roles/frr/
├── templates/
│   └── frr-pve.conf.j2      # FRR config template
├── tasks/
│   └── main.yml             # Deploy config + reload FRR
└── vars/
    └── main.yml             # VNI assignments, ASNs
```

**Manual Deployment:**
```bash
# Copy config to PVE host
scp frr.conf root@pve01:/etc/frr/frr.conf

# Validate syntax
ssh root@pve01 "vtysh -C -f /etc/frr/frr.conf"

# Apply configuration
ssh root@pve01 "systemctl reload frr"
```

### 8.3 Talos Node FRR Configuration

**Terraform Workflow:**
```bash
cd /Users/sulibot/repos/github/home-ops/terraform/infra/live/clusters/cluster-101

# Generate Talos machine configs with FRR config
cd config && terragrunt apply

# Apply configs to nodes
cd ../bootstrap && terragrunt apply
```

**Manual Config Application:**
```bash
# Export talosconfig
export TALOSCONFIG=/path/to/talosconfig

# Apply to single node
talosctl -n <node-ip> apply-config --file machineconfig-<node>.yaml

# Verify FRR container running
talosctl -n <node-ip> containers | grep frr

# Check FRR logs
talosctl -n <node-ip> logs ext-frr
```

### 8.4 Configuration Validation

**Proxmox VE Checks:**
```bash
ssh root@pve01

# Check BGP summary
vtysh -c "show bgp summary"
vtysh -c "show bgp vrf vrf_evpnz1 ipv6 summary"

# Check OSPF neighbors
vtysh -c "show ip ospf neighbor"
vtysh -c "show ipv6 ospf6 neighbor"

# Check EVPN
vtysh -c "show bgp l2vpn evpn summary"
vtysh -c "show evpn vni"

# Check routing table
vtysh -c "show ip route"
vtysh -c "show ipv6 route"
```

**Talos Node Checks:**
```bash
# Check BGP session
talosctl -n <node-ip> logs ext-frr | grep "neighbor.*Up"

# Check routes received
talosctl -n <node-ip> get routes | grep default

# Ping test from node
talosctl -n <node-ip> shell
ping -c 3 8.8.8.8
ping6 -c 3 2001:4860:4860::8888
```

### 8.5 Troubleshooting Common Issues

**Issue: BGP Session Not Establishing**

Check 1: Verify reachability
```bash
# From VM
ping6 fd00:101::fffe

# From PVE
ping6 fd00:101::11
```

Check 2: Verify BGP listen range
```bash
vtysh -c "show bgp vrf vrf_evpnz1 neighbors"
# Look for dynamic neighbor status
```

Check 3: Check FRR logs
```bash
# PVE
journalctl -u frr -f

# Talos
talosctl -n <node-ip> logs ext-frr --follow
```

**Issue: Routes Not Appearing in Routing Table**

Check 1: BGP route acceptance
```bash
vtysh -c "show bgp vrf vrf_evpnz1 ipv6"
# Verify routes are in BGP table
```

Check 2: Route-map filtering
```bash
vtysh -c "show route-map IMPORT-VM-ROUTES"
# Check permit/deny match clauses
```

Check 3: Next-hop reachability
```bash
vtysh -c "show bgp vrf vrf_evpnz1 ipv6 <prefix>"
# Verify next-hop is reachable
```

**Issue: VM Using Wrong BGP Source IP**

Symptom: Only one control plane node has BGP session

Check: FRR config on VMs
```bash
talosctl -n <node-ip> read /var/lib/frr/frr.conf | grep update-source
```

Expected: `neighbor fd00:101::fffe update-source fd00:101::XX`
Wrong: Missing `update-source` directive

Fix: Update Terraform template, reapply machine config

---

## 9. Traffic Flows and Forwarding Behavior

### 9.1 VM to Internet Traffic Flow

**Outbound Packet Flow:**
```
[VM solcp01]
  Source: fd00:101:fe::11 (loopback)
  Dest: 2001:4860:4860::8888 (Google DNS)

  ↓ (default route via fd00:101::fffe)

[PVE02 VRF vrf_evpnz1]
  L2: EVPN bridge (no VXLAN - local VM)
  L3: Routing lookup in VRF table
  Match: Default route via fd00:0:0:ffff::fffe (edge router)

  ↓ (route leaked to global table)

[PVE02 Global Table]
  Routing lookup: ::/0 → fd00:0:0:ffff::fffe (edge)
  OSPF next-hop: Via vmbr0.10

  ↓ (routed to edge)

[Edge Router]
  NAT66: fd00:101:fe::11 → 2600:xxxx:xxxx::1 (GUA)
  Forward to internet
```

**Return Packet Flow:**
```
[Internet]
  Source: 2001:4860:4860::8888
  Dest: 2600:xxxx:xxxx::1 (NAT66 address)

  ↓

[Edge Router]
  NAT66 reverse: 2600:xxxx:xxxx::1 → fd00:101:fe::11
  BGP lookup: fd00:101:fe::11/128 → fd00:0:0:ffff::2 (pve02)

  ↓ (forwarded to pve02)

[PVE02 Global Table]
  Import VRF route: fd00:101:fe::11 in VRF vrf_evpnz1

  ↓ (lookup in VRF)

[PVE02 VRF]
  BGP route: fd00:101:fe::11 via fd00:101::11 (VM)
  EVPN L2: Bridge forwarding (no VXLAN - local)

  ↓

[VM solcp01]
  Packet delivered
```

### 9.2 VM to VM Traffic Flow (Same Tenant, Same Host)

**Local Switching:**
```
[VM solwk02] fd00:101::22
  ↓ ARP/ND for fd00:101::21 (peer VM)

[PVE02 Bridge vmbr101v101]
  EVPN neighbor suppression: Bridge responds with peer MAC
  L2 forwarding: Direct bridge switching (no routing)

  ↓

[VM solwk01] fd00:101::21
```

**Key Point:** No BGP involved for same-subnet traffic

### 9.3 VM to VM Traffic Flow (Same Tenant, Different Host)

**VXLAN Overlay:**
```
[VM solcp01] fd00:101::11 (on pve01)
  Dest: fd00:101::12 (on pve02)

  ↓ ARP/ND for fd00:101::12

[PVE01 VRF vrf_evpnz1]
  EVPN learns: fd00:101::12 → MAC → VTEP fd00:0:0:ffff::2
  L2 forwarding decision: VXLAN encap required

  ↓ (VXLAN encap)

[PVE01 Global Table]
  Outer header:
    Source: fd00:0:0:ffff::1 (pve01 loopback)
    Dest: fd00:0:0:ffff::2 (pve02 loopback)
  OSPF routing: Via mesh link to pve02

  ↓ (routed via underlay)

[PVE02 Global Table]
  VXLAN decap

  ↓

[PVE02 VRF vrf_evpnz1]
  L2 forwarding to local VM

  ↓

[VM solcp02] fd00:101::12
```

### 9.4 Pod to Internet Traffic Flow (with Cilium BGP)

**When Cilium advertises pod networks:**
```
[Pod] fd00:101:244:0:abc::1
  Source: Pod IP
  Dest: 2001:4860:4860::8888

  ↓ (Cilium routes to node)

[Talos Node solwk01]
  Source NAT: fd00:101:244:0:abc::1 → fd00:101:fe::21 (node loopback)
  OR Direct routing if BGP advertises pod CIDR

  ↓ (via default route)

[PVE VRF] → [PVE Global] → [Edge] → [Internet]
  (same as VM to Internet flow)
```

---

## 10. Failure Scenarios and Recovery

### 10.1 Single PVE Host Failure

**Failure Event:** pve02 loses power

**Impact:**
- VMs on pve02: Offline (no HA configured)
- BGP sessions: Lost for VMs on pve02
- iBGP mesh: pve01 ↔ pve03 session remains
- EVPN: VNI remains active (2 of 3 VTEPs functional)

**Recovery:**
- VMs on pve01/pve03: No impact
- When pve02 restarts: BGP/OSPF/EVPN converge in <60s
- VM BGP sessions re-establish automatically

**Route Convergence Time:**
- OSPF detects failure: 40s (dead interval)
- BGP detects failure: 30s (hold timer)
- Route withdrawn from edge router: Immediate
- Traffic shifts to surviving PVE hosts: <60s total

### 10.2 Edge Router Failure

**Failure Event:** MikroTik edge router crashes

**Impact:**
- All internet connectivity lost
- iBGP mesh: Unaffected
- VM BGP sessions: Unaffected
- Internal routing (VM↔VM): Unaffected

**Recovery:**
- PVE detects BGP session down: 30s (hold timer)
- Default route withdrawn from VRF: Immediate
- VMs detect default route loss: 30s (BGP update)
- Outbound traffic: Black-holed until edge recovers

**Mitigation:**
- Deploy redundant edge routers
- Use BGP multipath for ECMP
- PVE would peer with both edges

### 10.3 EVPN Neighbor Suppression Issue

**Symptom:** VM cannot reach anycast gateway after migration

**Root Cause:**
- VM migrated from pve01 to pve02
- EVPN has not learned new VM location
- ARP/ND for gateway times out

**Debug:**
```bash
# On PVE, check EVPN neighbor table
vtysh -c "show evpn arp-cache vni 10101"

# Trigger neighbor learning
ping6 fd00:101::11
```

**Fix:**
- Ping VM from local PVE host
- EVPN learns MAC/IP binding
- Neighbor suppression starts working

**Prevention:**
- Ensure VMs send traffic on boot (gratuitous ARP)
- Monitor EVPN neighbor table

### 10.4 BGP Flapping Due to MTU Issues

**Symptom:** BGP sessions establish, then drop repeatedly

**Root Cause:**
- VXLAN overhead (50 bytes) exceeds link MTU
- TCP packets fragmented
- FRR drops fragmented BGP packets

**Debug:**
```bash
# Test MTU
ping6 -s 1450 -M do fd00:101::fffe

# Check for fragmentation
tcpdump -i ens18 'ip6[6] == 44'  # IPv6 fragment header
```

**Fix:**
- Set VM interface MTU to 1450
- OR Increase underlay MTU to 1550+
- Verify with ping tests

---

## 11. Operational Procedures

### 11.1 Adding a New VM to Tenant

**Prerequisites:**
- VM deployed via Terraform (cloud-init network config)
- FRR extension installed (Talos) or FRR package (Debian)
- Unique ASN assigned

**Steps:**
1. Deploy VM with correct network config
2. Verify VM has loopback IP configured
3. Verify FRR config includes BGP neighbor
4. Check BGP session established:
```bash
ssh root@pve01 "vtysh -c 'show bgp vrf vrf_evpnz1 ipv6 summary'"
```
5. Verify route advertisement:
```bash
ssh root@pve01 "vtysh -c 'show bgp vrf vrf_evpnz1 ipv6' | grep <vm-loopback>"
```
6. Test connectivity from VM:
```bash
ping6 2001:4860:4860::8888
```

**Rollback:**
- Shut down VM
- BGP session times out (30s)
- Routes automatically withdrawn

### 11.2 Maintenance: Draining a PVE Host

**Goal:** Migrate all VMs from pve02 before maintenance

**Procedure:**
1. Migrate VMs to other hosts:
```bash
pvesh get /cluster/resources --type vm | grep pve02
qm migrate <vmid> pve01
```
2. Wait for EVPN convergence (60s)
3. Verify BGP sessions moved:
```bash
vtysh -c "show bgp vrf vrf_evpnz1 ipv6 summary"
# Confirm sessions now on pve01/pve03
```
4. Gracefully shut down FRR:
```bash
systemctl stop frr
```
5. Perform maintenance
6. Restart FRR:
```bash
systemctl start frr
```
7. Verify iBGP mesh re-established:
```bash
vtysh -c "show bgp summary"
```

**Expected Downtime:**
- Per-VM: 5-10s (live migration)
- BGP convergence: 30-60s total

### 11.3 Changing FRR Configuration

**Proxmox VE Config Changes:**
```bash
# Edit Ansible template
vim roles/frr/templates/frr-pve.conf.j2

# Deploy to single host for testing
ansible-playbook -i inventory configure-frr.yml -l pve01 --check

# Apply to single host
ansible-playbook -i inventory configure-frr.yml -l pve01

# Verify no BGP sessions dropped
vtysh -c "show bgp summary"

# Deploy to remaining hosts
ansible-playbook -i inventory configure-frr.yml -l pve02,pve03
```

**Talos Node Config Changes:**
```bash
# Edit Terraform template
vim terraform/infra/modules/talos_config/frr.conf.j2

# Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# Apply to single node for testing
cd ../bootstrap
talosctl -n <node-ip> apply-config --file <config>.yaml

# Verify BGP session re-established
talosctl -n <node-ip> logs ext-frr | grep "neighbor.*Up"

# Apply to remaining nodes
terragrunt apply
```

### 11.4 Monitoring and Alerting

**Key Metrics to Monitor:**

1. **BGP Session State**
```bash
# Expected: All sessions "Established"
vtysh -c "show bgp summary" | grep -E "Established|Active|Connect"
```

2. **Route Counts**
```bash
# Expected: N loopback routes for N VMs
vtysh -c "show bgp vrf vrf_evpnz1 ipv6" | grep -c "fd00:101:fe::"
```

3. **EVPN VNI State**
```bash
# Expected: VNI in "Up" state
vtysh -c "show evpn vni" | grep 10101
```

4. **OSPF Neighbor State**
```bash
# Expected: "Full" state for all neighbors
vtysh -c "show ip ospf neighbor"
```

**Alerting Rules (Prometheus/Alertmanager):**
```yaml
- alert: BGPSessionDown
  expr: frr_bgp_peer_state != 6  # 6 = Established
  for: 2m
  annotations:
    summary: "BGP session down: {{ $labels.peer }}"

- alert: MissingVMRoute
  expr: count(frr_bgp_route{vrf="vrf_evpnz1"}) < expected_vm_count
  for: 5m
  annotations:
    summary: "Missing VM routes in VRF"
```

### 11.5 Configuration Backup and Disaster Recovery

**Backup FRR Configs:**
```bash
# Proxmox VE
scp root@pve01:/etc/frr/frr.conf backups/frr-pve01-$(date +%Y%m%d).conf

# Automated via Ansible
ansible pve-hosts -m fetch -a "src=/etc/frr/frr.conf dest=backups/"
```

**Restore from Backup:**
```bash
# Copy backup to host
scp backups/frr-pve01-20260103.conf root@pve01:/etc/frr/frr.conf

# Reload FRR
ssh root@pve01 "systemctl reload frr"

# Verify
ssh root@pve01 "vtysh -c 'show running-config'"
```

**Talos Config in Git:**
- Terraform state contains FRR configs
- Machine configs exported to git
- Disaster recovery: Re-run `terragrunt apply`

---

## Appendix A: Quick Reference

### BGP ASN Assignments
| Entity | ASN | Notes |
|--------|-----|-------|
| PVE Cluster | 4200001000 | iBGP mesh |
| Edge Router | 4200000000 | eBGP peer |
| Test VMs | 4200100000+ | Unique per VM |
| Talos CPs | 4210101011-19 | Cluster 101 |
| Talos Workers | 4210101021-99 | Cluster 101 |

### Key IP Addresses
| Function | IPv4 | IPv6 |
|----------|------|------|
| PVE Infra Loopbacks | 10.255.0.1-3 | fd00:0:0:ffff::1-3 |
| Edge Router | 10.255.0.254 | fd00:0:0:ffff::fffe |
| Tenant 101 Gateway | 10.101.0.254 | fd00:101::fffe |
| Tenant 101 VMs | 10.101.0.1-253 | fd00:101::1-fffd |
| Tenant 101 Loopbacks | 10.101.254.x | fd00:101:fe::x |

### FRR Commands
```bash
# Enter vtysh
vtysh

# Show configs
show running-config
show bgp summary
show bgp vrf <vrf> ipv6 summary
show ip route
show ipv6 route

# BGP route details
show bgp ipv6 <prefix>
show bgp vrf <vrf> ipv6 <prefix>

# Clear BGP sessions
clear bgp ipv6 *
clear bgp vrf <vrf> ipv6 *

# Debug
debug bgp neighbor-events
debug bgp updates
```

### Common Troubleshooting
| Issue | Command | Expected Output |
|-------|---------|-----------------|
| BGP session down | `show bgp summary` | State = Established |
| Routes missing | `show bgp ipv6` | Prefix present with valid next-hop |
| EVPN not working | `show evpn vni` | VNI state = Up |
| VM unreachable | `ping6 <vm-ip>` | Replies received |

---

## Appendix B: Configuration Templates

### Minimal VM FRR Config
```
frr version 10.2
frr defaults datacenter
hostname <node-name>
log syslog informational
service integrated-vtysh-config
!
ipv6 prefix-list DEFAULT-ONLY-v6 seq 10 permit ::/0
route-map IMPORT-DEFAULT-v6 permit 10
 match ipv6 address prefix-list DEFAULT-ONLY-v6
exit
route-map IMPORT-DEFAULT-v6 deny 90
exit
!
ipv6 prefix-list LOOPBACKS-V6 seq 10 permit fd00:101:fe::/64 ge 128
route-map ADVERTISE-LOOPBACKS-V6 permit 10
 match ipv6 address prefix-list LOOPBACKS-V6
exit
!
router bgp <local-asn>
 bgp router-id <loopback-ipv4>
 no bgp default ipv4-unicast
 no bgp default ipv6-unicast
 bgp graceful-restart
 timers bgp 10 30
 !
 neighbor fd00:101::fffe remote-as 4200001000
 neighbor fd00:101::fffe update-source <node-ipv6>
 neighbor fd00:101::fffe description "PVE Anycast Gateway"
 neighbor fd00:101::fffe capability extended-nexthop
 !
 address-family ipv6 unicast
  redistribute connected route-map ADVERTISE-LOOPBACKS-V6
  neighbor fd00:101::fffe activate
  neighbor fd00:101::fffe route-map IMPORT-DEFAULT-v6 in
  neighbor fd00:101::fffe route-map ADVERTISE-LOOPBACKS-V6 out
 exit-address-family
exit
!
line vty
!
```

### Minimal PVE VRF BGP Config
```
router bgp 4200001000 vrf vrf_evpnz1
 bgp router-id 10.255.0.<pve-id>
 no bgp default ipv4-unicast
 bgp listen limit 100
 !
 neighbor VMS peer-group
 neighbor VMS remote-as external
 neighbor VMS capability extended-nexthop
 !
 bgp listen range fd00:101::/64 peer-group VMS
 bgp listen range fd00:101:fe::/64 peer-group VMS
 !
 address-family ipv6 unicast
  neighbor VMS activate
  neighbor VMS route-map IMPORT-VM-ROUTES in
  neighbor VMS route-map EXPORT_TO_TALOS out
  redistribute connected route-map VRF_CONNECTED_V6
  import vrf default
 exit-address-family
exit
```

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-15 | Network Engineering | Initial draft |
| 2.0 | 2026-01-03 | Network Engineering | Added update-source requirement, Cilium integration, failure scenarios |

---

**END OF DOCUMENT**
