# FRR BGP Routing Architecture - Design Specification
**Multi-Tenant EVPN/VXLAN Datacenter with Kubernetes Integration**

**Document Type:** Network Architecture Design
**Author:** Network Engineering
**Date:** 2026-01-03
**Status:** Production

---

## Executive Summary

### Purpose

This document defines the routing architecture for a multi-tenant datacenter fabric using FRR (Free Range Routing) to provide:

1. **Layer 3 connectivity** for tenant workloads (VMs, Kubernetes pods) to external networks
2. **VM mobility** without renumbering or service interruption
3. **Tenant isolation** via VRF-based network segmentation
4. **Scalable route distribution** supporting hundreds of workloads per tenant
5. **Zero-touch workload onboarding** via dynamic BGP peering

### Design Philosophy

**Separation of Concerns:**
- **Infrastructure routing** (OSPF + iBGP + EVPN) provides underlay reachability and overlay signaling
- **Tenant routing** (eBGP) provides workload-to-infrastructure route exchange
- **No mixing** of infrastructure and tenant routes at any layer

**Identity vs. Topology:**
- Loopback addresses encode **identity** (who am I?)
- Physical interfaces encode **topology** (where am I?)
- Routing protocols resolve identity to topology dynamically

**Simplicity Over Optimization:**
- Default route only to workloads (no full table)
- Static anycast gateway (no VRRP/HSRP complexity)
- Dynamic BGP neighbors (no per-VM configuration)
- Explicit filtering (defense in depth)

### Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| **OSPF for underlay** | Mature, well-understood, fast convergence for infrastructure |
| **EVPN for overlay** | Industry-standard VXLAN control plane, MAC mobility support |
| **iBGP for infrastructure** | Route exchange between PVE hosts and edge router |
| **eBGP for tenants** | Simple, scalable, unique ASN per VM eliminates iBGP complexity |
| **VRF route leaking** | Bidirectional import/export without VPN/MPLS overhead |
| **Anycast gateway** | Eliminates FHRP, enables stateless VM placement |
| **IPv6-primary peering** | Future-proof, extended-nexthop for IPv4 over IPv6 |

---

## 1. Network Architecture Overview

### 1.1 Logical Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    INTERNET / WAN                           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ eBGP (AS 4200000000)
                         │
┌────────────────────────┴────────────────────────────────────┐
│              Edge Router (MikroTik RouterOS)                │
│  • Default route origination                                │
│  • NAT44 for IPv4 internet access                           │
│  • IPv6 routed end-to-end (no NAT66)                        │
│  • Route aggregation to upstream                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ eBGP + OSPF (management backup)
                         │
┌────────────────────────┴────────────────────────────────────┐
│         Proxmox VE Cluster (AS 4200001000)                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Infrastructure Routing Domain                │  │
│  │  • OSPF: Underlay (loopback-to-loopback)            │  │
│  │  • iBGP: Infrastructure route exchange              │  │
│  │  • EVPN: VXLAN overlay control plane                │  │
│  │                                                      │  │
│  │  [pve01]  ←iBGP/EVPN→  [pve02]  ←iBGP/EVPN→  [pve03]│  │
│  │  10.255.0.1           10.255.0.2          10.255.0.3│  │
│  │  fd00::ffff::1        fd00::ffff::2       fd00::ffff::3│
│  └──────────────────────────────────────────────────────┘  │
│                         │                                   │
│              ┌──────────┴──────────┐                        │
│              │   VRF Import/Export │                        │
│              └──────────┬──────────┘                        │
│  ┌──────────────────────┴────────────────────────────────┐ │
│  │         Tenant VRF (vrf_evpnz1)                       │ │
│  │  • EVPN/VXLAN: Layer 2 overlay (VNI 10101)          │ │
│  │  • Anycast Gateway: 10.101.0.254 / fd00:101::fffe   │ │
│  │  • BGP Listen Ranges: Dynamic VM peering            │ │
│  └──────────────────────┬────────────────────────────────┘ │
└─────────────────────────┼────────────────────────────────────┘
                          │
                          │ Dynamic eBGP (unique ASN per VM)
                          │
┌─────────────────────────┴────────────────────────────────────┐
│                  Tenant Workloads                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Talos CP     │  │ Talos Worker │  │ Test VM      │      │
│  │ AS 42101011  │  │ AS 42101021  │  │ AS 4200101006│      │
│  │              │  │              │  │              │      │
│  │ • Advertises │  │ • Advertises │  │ • Advertises │      │
│  │   loopback   │  │   loopback   │  │   loopback   │      │
│  │ • Receives   │  │ • Cilium BGP │  │ • Receives   │      │
│  │   default    │  │   for pods   │  │   default    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 Routing Domain Hierarchy

**Three distinct routing domains with controlled interaction:**

**Domain 1: Infrastructure (Global Default Table)**
- **Purpose:** Provide IP reachability for control plane communications
- **Protocols:** OSPF (underlay), iBGP (route exchange), EVPN (overlay signaling)
- **Scope:** Infrastructure loopbacks, management networks, fabric links
- **Isolation:** Never advertises tenant prefixes directly

**Domain 2: Tenant VRF (vrf_evpnz1)**
- **Purpose:** Isolate tenant networks, provide L3 gateway function
- **Protocols:** eBGP (VM peering), route import/export with global table
- **Scope:** Tenant subnets, VM loopbacks, pod networks
- **Isolation:** Cannot leak routes to other VRFs

**Domain 3: VM/Workload (BGP Client)**
- **Purpose:** Advertise workload identity, receive default route
- **Protocols:** eBGP client only (no IGP)
- **Scope:** Loopback address, pod CIDRs (Kubernetes nodes)
- **Isolation:** Cannot see other tenant routes

### 1.3 Multi-Tenant VRF Architecture

**Current Deployment:** Four tenant VRFs in production

| VRF Name | Tenant ID | VXLAN VNI | Subnets | Purpose |
|----------|-----------|-----------|---------|---------|
| vrf_evpnz1 | 100 | 10100 | 10.100.0.0/24, fd00:100::/64 | Tenant 100 workloads |
| vrf_evpnz1 | 101 | 10101 | 10.101.0.0/24, fd00:101::/64 | Talos Kubernetes cluster |
| vrf_evpnz1 | 102 | 10102 | 10.102.0.0/24, fd00:102::/64 | Tenant 102 workloads |
| vrf_evpnz1 | 103 | 10103 | 10.103.0.0/24, fd00:103::/64 | Tenant 103 workloads |

**Design Notes:**
- All tenants currently share VRF `vrf_evpnz1` (same routing domain)
- Isolation via VXLAN VNI (L2 separation)
- Future: Separate VRFs per tenant for true L3 isolation
- BGP listen ranges configured for all tenant subnets

**Scaling Pattern:**
```
# PVE VRF BGP config supports multiple tenants
bgp listen range fd00:100::/64 peer-group VMS
bgp listen range fd00:101::/64 peer-group VMS
bgp listen range fd00:102::/64 peer-group VMS
bgp listen range fd00:103::/64 peer-group VMS
bgp listen range fd00:100:fe::/64 peer-group VMS   # Loopbacks
bgp listen range fd00:101:fe::/64 peer-group VMS
bgp listen range fd00:102:fe::/64 peer-group VMS
bgp listen range fd00:103:fe::/64 peer-group VMS
```

### 1.4 Route Flow Architecture

**Northbound (VM → Internet):**
```
VM loopback → eBGP → VRF BGP table → import vrf → Global BGP table
→ eBGP → Edge router → Internet
```

**Southbound (Internet → VM):**
```
Default route → eBGP → Global BGP table → import vrf → VRF BGP table
→ eBGP → VM routing table
```

**Critical Design Point:** Bidirectional route leaking via `import vrf` eliminates need for VPN/MPLS complexity while maintaining VRF isolation.

**Workstation Access to VMs:**
```
Workstation (10.0.10.x) → Edge Router → PVE (Global Table) → VRF Import → VM

Flow:
1. Workstation on management network (10.0.10.0/24)
2. Edge router has routes to VM loopbacks (learned via BGP from PVE)
3. Edge router forwards to PVE infrastructure loopback
4. PVE global table has VM routes (imported from VRF)
5. Lookup routes packet to VRF (VRF has connected routes to VM subnets)
6. Packet delivered to VM

Return path:
1. VM uses default route → Anycast gateway in VRF
2. VRF routes to global table (VRF imports global routes)
3. Global table routes to edge router
4. Edge router routes to workstation
```

**Key Point:** VMs advertise their loopbacks via BGP, which propagates to edge router. Workstations can then reach VMs without VMs needing to advertise infrastructure space.

---

## 2. Control Plane Design

### 2.1 Protocol Selection Rationale

**Why OSPF for Underlay (Not BGP, Not IS-IS)?**

| Protocol | Pros | Cons | Decision |
|----------|------|------|----------|
| **OSPF** | • Mature, widely deployed<br>• Fast convergence (sub-second)<br>• Simple area design (single area 0)<br>• Native IPv4/IPv6 support | • Not designed for Internet-scale<br>• Manual summarization | ✅ **Selected** - Perfect fit for 3-node infrastructure |
| **IS-IS** | • Clean protocol design<br>• Single protocol for IPv4/IPv6 | • Less common skillset<br>• Overkill for small fabric | ❌ Rejected - Unnecessary complexity |
| **iBGP** | • Unified protocol stack | • Requires IGP for reachability anyway<br>• Slower convergence | ❌ Rejected - Underlay needs fast failover |

**Why iBGP for Infrastructure Route Exchange?**

- Provides **route reflection** for EVPN (full mesh for 3 nodes is acceptable)
- Enables **policy-based routing** via route-maps (OSPF cannot)
- Supports **multiple address families** (IPv4, IPv6, EVPN) in single session
- **Next-hop preservation** critical for EVPN overlay

**Why eBGP for Tenant Peering (Not iBGP)?**

| Design | Behavior | Issues |
|--------|----------|--------|
| **iBGP** | All VMs in same AS | • Requires full mesh or route reflectors<br>• AS-path loop prevention breaks with VM migration<br>• Synchronization delays |
| **eBGP** | Each VM unique AS | • No mesh required (each peers with gateway only)<br>• No loop prevention issues<br>• Instant route propagation | ✅ **Selected** |

**Critical Insight:** Using `remote-as external` with BGP listen ranges allows VMs to self-assign ASNs without PVE-side configuration.

### 2.2 OSPF Design

**Design Goals:**
1. Advertise infrastructure loopbacks only (never tenant routes)
2. Minimize convergence time (subsecond preferred)
3. Prevent accidental adjacencies on tenant interfaces
4. Provide backup path via management network

**Topology:**
```
                    [dummy_underlay]
                    10.255.0.1/32
                    fd00:0:0:ffff::1/128
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
   [vmbr1v20]         [vmbr1v21]        [vmbr0.10]
   to pve02           to pve03          to RouterOS
   cost 10            cost 10           cost 1000
   point-to-point     point-to-point    broadcast
```

**Area Design:**
- **Single Area 0.0.0.0** - No ABR/ASBR complexity needed for 3 nodes
- **No area summarization** - Full loopback reachability required for BGP next-hop

**Network Type Selection:**

| Interface | OSPF Network Type | Rationale |
|-----------|-------------------|-----------|
| Mesh links (vmbr1vXX) | `point-to-point` | • No DR/BDR election overhead<br>• Faster convergence (10s → <1s)<br>• Only 2 routers per segment |
| Management (vmbr0.10) | `broadcast` | • Multiple devices on segment (PVE + RouterOS)<br>• Standard DR/BDR election |
| Loopback (dummy_underlay) | `broadcast` + `passive` | • Never sends OSPF packets<br>• Advertised in router LSA |

**Cost Strategy:**
- **Mesh links: 10** - Primary forwarding path, all links equal cost
- **Management: 1000** - Backup only, avoids hairpinning traffic through edge router
- **Result:** Traffic uses direct mesh, falls back to management if mesh fails

**Passive Interface Design:**
```
passive-interface default              ← All interfaces passive by default
no passive-interface vmbr1v20          ← Explicitly enable on mesh
no passive-interface vmbr1v21
no passive-interface vmbr0.10          ← Enable on management
no passive-interface dummy_underlay    ← Advertise but don't send Hello
```

**Why This Matters:** Prevents OSPF adjacencies from forming on tenant VRF bridges (vmbr101v101, etc.), avoiding route leakage and security issues.

**Redistribution Strategy:**
- **OSPFv2:** `redistribute kernel route-map OSPF_INFRA_V4`
- **OSPFv3:** `redistribute connected route-map OSPF_INFRA_V6`
- **Filter:** Only permit `10.255.0.0/16` and `fd00:0:0:ffff::/64` (infrastructure loopbacks)
- **Why kernel vs connected?** IPv4 loopbacks configured via kernel, IPv6 via interface config

### 2.3 iBGP Design (Infrastructure)

**Topology:** Full mesh between 3 PVE hosts

**Session Design:**
- **Peering:** Loopback-to-loopback (requires OSPF for reachability)
- **Update source:** Always infrastructure loopback (not physical interface)
- **Next-hop behavior:** Preserve for EVPN, set next-hop-self for edge router

**Address Family Architecture:**

```
router bgp 4200001000
  │
  ├─ address-family ipv4 unicast
  │    • Advertise: Infrastructure connected routes
  │    • Import: Tenant routes from VRF (via import vrf)
  │    • Export to edge: Tenant routes only (filtered)
  │
  ├─ address-family ipv6 unicast
  │    • Advertise: Infrastructure connected routes
  │    • Import: Tenant routes from VRF (via import vrf)
  │    • Export to edge: Tenant routes only (filtered)
  │
  └─ address-family l2vpn evpn
       • Advertise: All local VNIs (advertise-all-vni)
       • Advertise: SVI IP addresses (advertise-svi-ip)
       • No route filtering (trust iBGP peers)
```

**Why Three Separate Address Families?**
- **IPv4 unicast:** Tenant IPv4 routes (10.101.0.0/24, 10.101.254.0/24)
- **IPv6 unicast:** Tenant IPv6 routes (fd00:101::/64, fd00:101:fe::/64)
- **L2VPN EVPN:** MAC/IP bindings for VXLAN overlay (separate namespace)

**Critical Configuration: `no bgp default ipv4-unicast`**
- Without this, BGP auto-activates all neighbors in IPv4 unicast AF
- Causes route leakage and unintended advertisements
- **Must explicitly activate** neighbors in each AF

**Next-Hop Handling:**

| Scenario | Next-Hop Behavior | Reason |
|----------|-------------------|--------|
| iBGP → iBGP | Preserved | Next-hop is infrastructure loopback (always reachable) |
| VRF → Global | Rewritten to PVE loopback | VM IPs not in global routing table |
| Global → Edge | `next-hop-self force` | Edge cannot reach VM IPs directly |
| iBGP → VRF | Preserved | Allows ECMP across multiple PVE hosts |

### 2.4 EVPN Design

**Purpose:** Control plane for VXLAN overlay, eliminates data-plane MAC learning

**EVPN Route Types Used:**

| Type | Name | Purpose in This Design |
|------|------|------------------------|
| Type 2 | MAC/IP Advertisement | Advertise VM MAC+IP to other VTEPs |
| Type 3 | Inclusive Multicast | Advertise VTEP membership for BUM traffic |

**Not Used:**
- **Type 1** (Ethernet Auto-Discovery) - No Ethernet segments, VMs not multihomed
- **Type 4** (Ethernet Segment Route) - No ES/LAG (Link Aggregation Groups) configured
- **Type 5** (IP Prefix Route) - Using VRF route import/export instead (simpler than EVPN Type 5)

**Why Not Type 5?**
- Type 5 routes advertise L3 prefixes via EVPN
- We use standard BGP VRF import/export for L3 routing (simpler, more flexible)
- Type 5 would add unnecessary complexity for 3-node cluster

**EVPN Configuration Philosophy:**
```
address-family l2vpn evpn
  advertise-all-vni      ← Advertise all local VNIs automatically
  advertise-svi-ip       ← Advertise anycast gateway IP
```

**Why `advertise-all-vni`?**
- Eliminates manual VNI configuration per bridge
- New tenant VRFs auto-participate in EVPN
- Scales to hundreds of VNIs without config changes

**Neighbor Suppression:**
- Enabled on all VXLAN bridges (`bridge-arp-nd-suppress on`)
- Bridge responds to ARP/ND locally if MAC/IP known via EVPN
- Eliminates ARP broadcast across VXLAN fabric
- **Critical for anycast gateway:** Ensures VMs always resolve gateway to local PVE

**VTEP Source:**
- Always infrastructure loopback IPv4 (`10.255.0.X`)
- **FRR Limitation:** VXLAN requires IPv4 VTEP addresses (IPv6 not supported)
- OSPF ensures all VTEPs can reach each other via IPv4
- EVPN Type 3 routes advertise VTEP membership

### 2.5 VRF BGP Design (Tenant Routing)

**Design Goals:**
1. Accept BGP connections from any VM in tenant subnet (dynamic peering)
2. Unique ASN per VM without manual configuration
3. Filter VM advertisements (accept only loopbacks/pods)
4. Export default route + peer loopbacks to VMs

**Dynamic Neighbor Architecture:**
```
router bgp 4200001000 vrf vrf_evpnz1
  neighbor VMS peer-group
  neighbor VMS remote-as external    ← Any ASN except 4200001000

  bgp listen range fd00:101::/64 peer-group VMS       ← Tenant subnet
  bgp listen range fd00:101:fe::/64 peer-group VMS    ← Tenant loopbacks
```

**How BGP Listen Works:**
1. VM initiates TCP connection to `fd00:101::fffe:179` (BGP port)
2. PVE checks source IP against listen ranges
3. If match, PVE accepts connection and creates dynamic neighbor
4. Neighbor inherits all peer-group settings (AS external, route-maps, etc.)
5. VM's ASN learned from BGP OPEN message

**Why This Scales:**
- No per-VM configuration on PVE side
- VMs can be added/removed without PVE changes
- Supports 100+ VMs (configurable via `bgp listen limit`)

**Route Filtering Philosophy:**

**Inbound (VM → PVE):**
```
Accept:
  • VM loopbacks: 10.101.254.0/24 as /32 hosts
  • VM loopbacks: fd00:101:fe::/64 as /128 hosts
  • Pod CIDRs: 10.101.244.0/22 (Kubernetes)
  • Pod CIDRs: fd00:101:244::/60 (Kubernetes)

Deny:
  • Infrastructure space (10.255.x.x, fd00:0:0:ffff::/48)
  • Default routes (prevents route injection)
  • Anything else (implicit deny-all)
```

**Outbound (PVE → VM):**
```
Advertise:
  • Default routes: 0.0.0.0/0, ::/0
  • Peer loopbacks: Other VM loopbacks in same VRF

Do NOT advertise:
  • Full routing table
  • Infrastructure routes
  • Other tenant routes
```

**Why Advertise Peer Loopbacks?**
- Kubernetes nodes need direct node-to-node communication (etcd, kubelet)
- Without peer loopbacks, traffic hairpins through anycast gateway
- With peer loopbacks, nodes route directly to each other

**VRF Route Leaking:**
```
router bgp 4200001000 vrf vrf_evpnz1
  address-family ipv6 unicast
    import vrf default    ← Import global routes (default route) to VRF

router bgp 4200001000
  address-family ipv6 unicast
    import vrf vrf_evpnz1 ← Import VRF routes (VM loopbacks) to global
```

**Bidirectional Import Semantics:**
- `import vrf default` in VRF: Brings default route from global → VRF → VMs
- `import vrf vrf_evpnz1` in global: Brings VM loopbacks from VRF → global → edge
- **No route tags required** - FRR handles loop prevention automatically

---

## 3. ASN Allocation Strategy

### 3.1 ASN Namespace Design

**Design Principle:** ASN encodes identity and role, not topology

**Infrastructure ASNs:**
```
4200001000    Proxmox VE cluster (iBGP domain)
4200000000    Edge router
```

**Tenant ASN Patterns:**

**Test VMs (Non-Kubernetes):**
```
Format: 42001<tenant_id><vm_suffix>

Example for tenant 101:
  4200101001 - 4200101099   Available for test VMs
  4200101006                debian-test-1 (actual)
  4200101007                debian-test-2 (actual)
```

**Talos/Kubernetes Nodes:**
```
Format: 421<cluster_id><node_type><node_suffix>

Where:
  cluster_id:   0101 (for tenant 101)
  node_type:    01 (control plane), 02 (worker)
  node_suffix:  11-19 (CP), 21-99 (workers)

Examples:
  4210101011    solcp01 (control plane node 11)
  4210101012    solcp02 (control plane node 12)
  4210101013    solcp03 (control plane node 13)
  4210101021    solwk01 (worker node 21)
  4210101022    solwk02 (worker node 22)
  4210101023    solwk03 (worker node 23)
```

### 3.2 ASN Allocation Rationale

**Why Unique ASN Per VM?**

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **All VMs same AS (iBGP)** | Standard design | • Requires route reflector or full mesh<br>• AS-path loop prevention<br>• Slow convergence | ❌ Rejected |
| **VMs in different AS (eBGP)** | • Simple hub-and-spoke<br>• Fast convergence<br>• No RR needed | Requires unique ASN per VM | ✅ **Selected** |

**Why Encode Identity in ASN?**
- **Troubleshooting:** `show bgp summary` immediately shows which node/role
- **Automation:** ASN pattern can be generated from node metadata
- **Security:** ASN mismatch detection (VM using wrong identity)

**ASN Assignment Automation:**
```
# Terraform example
local_asn = format("421%04d%02d%02d",
  var.cluster_id,           # 0101
  var.node_type,            # 01 or 02
  var.node_suffix           # 11-99
)
```

---

## 4. Anycast Gateway Architecture

### 4.1 Why Anycast (Not VRRP/HSRP)?

| Protocol | Behavior | Issues in EVPN |
|----------|----------|----------------|
| **VRRP/HSRP** | Active/Standby with VIP failover | • Control plane overhead (hello packets)<br>• VXLAN ARP sync complexity<br>• Sub-optimal forwarding (hairpinning) |
| **Anycast** | All hosts answer for same IP | • Stateless (no elections)<br>• Optimal forwarding (local PVE always)<br>• Works naturally with EVPN neighbor suppression | ✅ **Selected** |

### 4.2 Anycast Semantics

**Configuration:**
```
All PVE hosts have identical configuration:
  vmbr101v101:  10.101.0.254/24, fd00:101::fffe/64

VMs see:
  Gateway: 10.101.0.254 / fd00:101::fffe

Actual forwarding:
  VM on pve01 → ARP for gateway → pve01 responds (EVPN neighbor suppression)
  VM on pve02 → ARP for gateway → pve02 responds (EVPN neighbor suppression)
```

**Critical Dependency: EVPN Neighbor Suppression**

Without neighbor suppression:
```
VM on pve01 → ARP for fd00:101::fffe → Broadcast across VXLAN
  → pve01, pve02, pve03 all respond → ARP conflict
```

With neighbor suppression:
```
VM on pve01 → ARP for fd00:101::fffe → Local bridge intercepts
  → Bridge checks EVPN table → Finds MAC belongs to local VTEP
  → Bridge responds with local MAC → No VXLAN traffic
```

**How VM Finds Correct PVE During BGP Peering:**

1. VM sends BGP SYN to `fd00:101::fffe:179`
2. VM's ARP/ND: "Who has fd00:101::fffe?"
3. Local PVE bridge (EVPN neighbor suppression): "I do, here's my MAC"
4. Packet forwarded to local PVE (no VXLAN)
5. BGP session established with hosting PVE

**Failure Mode: VM Migration During BGP Session**

```
Initial state:
  VM on pve01 → BGP session with pve01

VM migrated to pve02:
  → BGP session breaks (source IP unchanged, but L2 path changed)
  → VM TCP retransmit → ARP for gateway
  → pve02 responds (EVPN learned new location)
  → New BGP session establishes with pve02
  → Convergence time: ~30s (BGP hold timer)
```

### 4.3 Anycast + BGP Interaction

**Design Constraint:** VMs must use primary IP (not VIP) as BGP source

**Problem Without `update-source`:**
```
Talos control plane nodes:
  ens18:  fd00:101::11/64    (primary IP)
  lo:     fd00:101::10/128   (Kubernetes VIP, shared across 3 CPs)

FRR auto-selects source IP:
  → Routing table lookup for fd00:101::fffe
  → Both IPs valid, prefers /128 over /64 (more specific)
  → Uses fd00:101::10 as source

Result:
  → All 3 CPs use same source IP
  → Only 1 BGP session established
  → 2 CPs have no routing
```

**Solution:**
```
neighbor fd00:101::fffe update-source fd00:101::11
```
- Explicitly forces FRR to use primary IP
- Each CP uses unique source IP
- All 3 BGP sessions establish independently

**Why This Matters for Kubernetes:**
- Control plane VIP is **required** for kube-apiserver HA
- Without all 3 CPs having BGP, pod networks not fully advertised
- Pods on nodes without BGP are unreachable from outside cluster

---

## 5. Route Advertisement Policy

### 5.1 Policy Design Principles

**Defense in Depth:**
- **Inbound filters:** Accept only expected routes (whitelist approach)
- **Outbound filters:** Advertise only intended routes (whitelist approach)
- **Implicit deny-all:** Every route-map ends with explicit deny

**Tenant Isolation:**
- VMs **cannot** advertise infrastructure space back to PVE (prevents route hijacking)
- VMs **cannot** advertise other tenant space (VRF isolation)
- VMs **cannot** advertise default route to PVE (prevents route injection)
- **Note:** Workstation access to VMs uses infrastructure routing (management network → VRF), not BGP advertisements from VMs

**Infrastructure Protection:**
- PVE **never** advertises infrastructure space to edge router
- PVE **never** leaks tenant routes to other VRFs
- PVE **never** accepts infrastructure routes from VMs

### 5.2 Route Filtering Requirements

**VM → PVE VRF (Inbound to Infrastructure):**

| Prefix Type | Action | Rationale |
|-------------|--------|-----------|
| VM loopback (/32, /128) | **Accept** | Required for VM reachability, stable identity |
| Pod CIDR (/22-/24, /60-/64) | **Accept** | Required for Kubernetes pod-to-pod and external access |
| Tenant subnet (/24, /64) | **Deny** | Already known via connected routes |
| Default route (0.0.0.0/0, ::/0) | **Deny** | Prevents route injection attack |
| Infrastructure space | **Deny** | Security - VMs cannot hijack infrastructure IPs |
| Anything else | **Deny** | Implicit deny-all |

**PVE VRF → Global Table (Export to Edge):**

| Prefix Type | Action | Rationale |
|-------------|--------|-----------|
| VM loopback (/32, /128) | **Accept** | Required for return path from internet |
| Pod CIDR (/22-/24, /60-/64) | **Accept** | Required for pod-to-internet traffic |
| Tenant GUA prefixes | **Accept** | If PD delegation exists, must announce to edge |
| Infrastructure loopbacks | **Deny** | Should use OSPF, not BGP to edge |
| Default route | **Deny** | We receive default, not advertise it |
| Anything else | **Deny** | Implicit deny-all |

**PVE Global → PVE VRF (Import to Tenant):**

| Prefix Type | Action | Rationale |
|-------------|--------|-----------|
| Default route (0.0.0.0/0, ::/0) | **Accept** | VMs need default for internet access |
| VM loopbacks (peers) | **Accept** | Enables direct node-to-node traffic |
| Anything else | **Deny** | VMs don't need full routing table |

**PVE VRF → VM (Outbound to Workload):**

| Prefix Type | Action | Rationale |
|-------------|--------|-----------|
| Default route | **Accept** | VM's primary routing need |
| Peer loopbacks | **Accept** | Direct node-to-node for Kubernetes |
| Tenant subnet | **Deny** | Already known via local interface |
| Anything else | **Deny** | Minimize routing table size on VMs |

### 5.3 Prefix-List Design Patterns

**Exact Match Pattern:**
```
ip prefix-list DEFAULT seq 5 permit 0.0.0.0/0
# Matches ONLY 0.0.0.0/0, nothing else
```

**Host Route Pattern:**
```
ip prefix-list LOOPBACKS seq 10 permit 10.101.254.0/24 ge 32 le 32
# Matches any /32 within 10.101.254.0/24
# ge = "greater or equal" (must be /32 or longer)
# le = "less or equal" (must be /32 or shorter)
# Result: Only /32 hosts match, not /24 or /31
```

**Subnet and More-Specifics Pattern:**
```
ipv6 prefix-list POD_CIDRS seq 5 permit fd00:101:244::/60 le 64
# Matches fd00:101:244::/60 and any subnet within it down to /64
# Example: fd00:101:244::/60, fd00:101:244::/62, fd00:101:244:0::/64
```

**Deny-All Pattern:**
```
ip prefix-list FILTER seq 99 deny 0.0.0.0/0 le 32
# Matches ANY IPv4 prefix (0.0.0.0/0 le 32 = "all prefixes")
# Must be last entry in prefix-list
```

### 5.4 Next-Hop Rewrite Strategy

**Critical for VRF Route Leaking:**

When importing from VRF to global table:
```
Problem:
  VM advertises fd00:101:fe::11/128 with next-hop = fd00:101::11
  This is imported to global table
  Edge router receives route with next-hop = fd00:101::11
  But fd00:101::11 is NOT in edge router's routing table (it's in VRF!)

Solution:
  PVE rewrites next-hop to self before advertising to edge
  route-map EXPORT_TO_ROUTEROS permit 10
    set ipv6 next-hop global fd00:0:0:ffff::<PVE_ID>
```

**Result:**
- Edge router sees: fd00:101:fe::11/128 via fd00:0:0:ffff::1 (pve01 loopback)
- OSPF provides path to fd00:0:0:ffff::1
- Return traffic routed correctly

---

## 6. Kubernetes Integration

### 6.1 Dual BGP Architecture

**Current State:** FRR on Talos host advertises node loopback only

**Future State:** Cilium BGP advertises pod CIDRs

```
┌─────────────────────────────────────────────────────┐
│              Talos Node (solwk01)                   │
│                                                     │
│  ┌─────────────────────────────────────────────┐  │
│  │  FRR (Host BGP)                             │  │
│  │  • Advertises: Node loopback (fd00:101:fe::21) │
│  │  • Imports: Default route, peer loopbacks   │  │
│  │  • AS: 4210101021                           │  │
│  └─────────────────────────────────────────────┘  │
│                      │                             │
│                      │ (Future integration)        │
│                      ↓                             │
│  ┌─────────────────────────────────────────────┐  │
│  │  Cilium BGP Control Plane                   │  │
│  │  • Advertises: Pod CIDR (fd00:101:244::/60) │  │
│  │  • Advertises: LoadBalancer VIPs            │  │
│  │  • Coordinates with host FRR via BFD        │  │
│  └─────────────────────────────────────────────┘  │
│                                                     │
│                      │ eBGP                         │
│                      ↓                             │
└──────────────────────┼──────────────────────────────┘
                       │
                       ↓
           ┌───────────────────────┐
           │  PVE VRF BGP          │
           │  Accepts both:        │
           │  • Node loopbacks     │
           │  • Pod CIDRs          │
           └───────────────────────┘
```

### 6.2 Why Separate FRR and Cilium BGP?

**Design Decision:** Do NOT merge host BGP and Cilium BGP into single daemon

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **Single FRR (merge)** | Unified config | • FRR not Kubernetes-aware<br>• Pod CIDR allocation is dynamic<br>• No integration with Cilium datapath | ❌ Rejected |
| **Cilium BGP only** | Native K8s integration | • Cannot advertise node loopback<br>• Breaks host-level routing | ❌ Rejected |
| **Dual BGP (FRR + Cilium)** | • Each handles its domain<br>• FRR stable (host)<br>• Cilium dynamic (pods) | Need coordination | ✅ **Selected** |

**Coordination Mechanism:**
- FRR advertises node loopback (static, never changes)
- Cilium advertises pod CIDRs (dynamic, changes with pod scheduling)
- Both peer with same PVE gateway (fd00:101::fffe)
- PVE aggregates both route types
- BFD between FRR ↔ Cilium ensures consistency

### 6.3 Pod Network Advertisement Requirements

**Pod CIDR Allocation Pattern:**
```
Cluster-wide pod CIDR: fd00:101:244::/60 (4096 /64 subnets)

Per-node allocation:
  solcp01: fd00:101:244:0::/64
  solcp02: fd00:101:244:1::/64
  solcp03: fd00:101:244:2::/64
  solwk01: fd00:101:244:3::/64
  solwk02: fd00:101:244:4::/64
  solwk03: fd00:101:244:5::/64
```

**Advertisement Strategy:**
- Cilium advertises **per-node /64** (not cluster-wide /60)
- PVE accepts /60 - /64 range (prefix-list: `fd00:101:244::/60 le 64`)
- Edge router receives all /64s, can summarize to /60 if desired

**Why Not Advertise Cluster-Wide /60?**
- ECMP breaks pod-to-pod communication (wrong PVE receives traffic)
- Need per-node /64 for correct forwarding path
- PVE routes to node hosting that /64 subnet

**LoadBalancer VIP Advertisement:**
```
VIP pool: fd00:101:240::/24 (future: fd00:101:fffe::/112)

Cilium BGP behavior:
  • Advertises VIP only from nodes running the pods
  • Withdraws VIP when all pods die
  • Enables active-active LB with ECMP
```

---

## 7. Failure Modes and Convergence

### 7.1 Single PVE Host Failure

**Failure Scenario:** pve02 loses power

**Impact Cascade:**
```
T+0s:    pve02 goes offline
T+1s:    OSPF dead interval expires (neighbors detect failure)
T+1s:    OSPF recalculates SPF, removes pve02 routes
T+30s:   iBGP hold timer expires on pve01, pve03
T+30s:   BGP routes from pve02 withdrawn
T+30s:   EVPN Type 3 routes withdrawn (VNI 10101 on pve02)
T+30s:   VMs on pve02 lose BGP sessions
T+31s:   Edge router receives BGP withdrawals for pve02-hosted VMs
```

**Traffic Impact:**

| Traffic Flow | Status | Recovery |
|--------------|--------|----------|
| VM-to-VM (same host) | ✅ Unaffected | N/A - local switching |
| VM-to-VM (cross-host via VXLAN) | ⚠️ Partial failure | VMs on pve02 unreachable, others work |
| VM-to-internet (pve02 VMs) | ❌ Failed | No path until pve02 recovers |
| VM-to-internet (other VMs) | ✅ Unaffected | pve01/pve03 still forward |

**Convergence Time:**
- **OSPF:** 1 second (dead interval)
- **BGP:** 30 seconds (hold timer)
- **Total:** 30 seconds until full convergence

**Recovery:**
```
pve02 powered on
T+0s:    OSPF adjacencies form with pve01, pve03
T+10s:   iBGP sessions establish (keepalive 10s)
T+15s:   EVPN routes exchanged, VNI 10101 active
T+30s:   VMs on pve02 restart, BGP sessions establish
T+60s:   Full convergence, all routes restored
```

### 7.2 Edge Router Failure

**Failure Scenario:** MikroTik edge router crashes

**Impact Cascade:**
```
T+0s:    Edge router offline
T+30s:   All PVE hosts detect BGP session down
T+30s:   Default route withdrawn from global table
T+31s:   Default route withdrawn from VRF table
T+31s:   VMs receive BGP update withdrawing ::/0 and 0.0.0.0/0
```

**Traffic Impact:**

| Traffic Flow | Status | Notes |
|--------------|--------|-------|
| VM-to-VM (any) | ✅ Unaffected | All internal routing intact |
| VM-to-internet | ❌ Black-holed | No default route, packets dropped at VM |
| Internet-to-VM | ❌ Black-holed | No upstream path, packets never reach datacenter |
| Infrastructure | ✅ Unaffected | OSPF + iBGP still functional |

**Mitigation Strategy (Not Implemented):**
```
Dual edge routers:
  edge01: 10.255.0.253 / fd00:0:0:ffff::fffd
  edge02: 10.255.0.254 / fd00:0:0:ffff::fffe

PVE configuration:
  • Peer with both edges via eBGP
  • Both advertise default route with same weight
  • BGP multipath for ECMP load balancing

Failure behavior:
  • One edge fails → Other continues advertising default
  • Convergence time: 30s (BGP hold timer)
  • No traffic loss (ECMP maintains connectivity)
```

### 7.3 EVPN Neighbor Suppression Failure

**Failure Scenario:** VM migrated from pve01 to pve03, EVPN has not learned new location

**Symptom:**
```
VM sends ARP request for anycast gateway fd00:101::fffe
  → Broadcast across VXLAN (neighbor suppression not working)
  → Multiple PVE hosts respond
  → VM receives conflicting ARP replies
  → Networking unstable (flapping between PVE hosts)
```

**Root Cause:**
- EVPN Type 2 route not updated after migration
- PVE03 bridge does not have VM MAC in local table
- Neighbor suppression fails, falls back to broadcast

**Detection:**
```
# On PVE03 (new host)
vtysh -c "show evpn mac vni 10101" | grep <vm-mac>
# Expected: MAC present with local VTEP
# Actual: MAC missing or pointing to pve01

# On VM
ip -6 neigh show dev ens18
# Expected: fd00:101::fffe lladdr <pve03-mac> REACHABLE
# Actual: fd00:101::fffe lladdr <pve01-mac> STALE (wrong PVE)
```

**Fix:**
```
# Force EVPN to learn VM location
ssh root@pve03 "ping6 -c 2 fd00:101::11"

# Verify EVPN learned MAC
vtysh -c "show evpn mac vni 10101" | grep <vm-mac>
# Should now show local VTEP

# VM's ARP/ND should resolve correctly
# BGP session should establish with pve03
```

**Prevention:**
- Ensure VM sends gratuitous ARP on boot (cloud-init)
- Monitor EVPN MAC table for missing entries
- Implement VM migration hooks to trigger neighbor learning

### 7.4 BGP Flapping Due to MTU

**Failure Scenario:** BGP sessions establish, then drop within seconds, repeatedly

**Root Cause:**
```
VXLAN overhead: 50 bytes (outer IP + UDP + VXLAN header)
Link MTU: 1500 bytes
Effective MTU: 1450 bytes

BGP behavior:
  1. TCP SYN (small packet) → Succeeds
  2. BGP OPEN (small packet) → Succeeds
  3. BGP UPDATE (large packet with full routing table) → Fragmented
  4. FRR receives fragmented TCP packet → Drops (security policy)
  5. TCP retransmit → Fragmented again → Dropped
  6. TCP timeout → Session closed
  7. Repeat
```

**Detection:**
```
# Check BGP session state
vtysh -c "show bgp vrf vrf_evpnz1 ipv6 summary"
# Look for: Up/Down column showing <1m (rapid flapping)

# Test MTU from VM
ping6 -s 1400 -M do fd00:101::fffe   # Success
ping6 -s 1500 -M do fd00:101::fffe   # Failure (packet too big)

# Check for fragmentation
talosctl -n <vm-ip> logs ext-frr | grep "fragmented\|MTU"
```

**Fix:**
```
Option 1: Reduce VM MTU (immediate)
  netplan: mtu: 1450

Option 2: Increase underlay MTU (requires infrastructure change)
  PVE physical interfaces: MTU 1550+
  Switch ports: MTU 9000 (jumbo frames)
```

**Long-term Solution:**
- Deploy jumbo frames (MTU 9000) on underlay
- Set tenant interfaces to MTU 1500 (standard)
- VXLAN overhead absorbed by extra headroom

---

## 8. Monitoring and Observability

### 8.1 Key Metrics

**BGP Health:**
```
Metric: frr_bgp_peer_state
Expected: 6 (Established)
Alert: != 6 for >2 minutes

Metric: frr_bgp_peer_uptime_seconds
Expected: Increasing
Alert: Resets frequently (flapping)

Metric: frr_bgp_prefixes_received
Expected: Known count (e.g., 1 for default-only VMs)
Alert: 0 (not receiving routes)

Metric: frr_bgp_prefixes_advertised
Expected: 1+ (at least loopback)
Alert: 0 (not advertising routes)
```

**OSPF Health:**
```
Metric: frr_ospf_neighbor_state
Expected: Full
Alert: != Full for >1 minute

Metric: frr_ospf_interface_state
Expected: Point-to-Point or DR/BDR
Alert: Down
```

**EVPN Health:**
```
Metric: frr_evpn_vni_state
Expected: Up
Alert: Down for >2 minutes

Metric: frr_evpn_mac_count{vni="10101"}
Expected: Number of VMs in tenant
Alert: <expected_count (MACs not learned)
```

### 8.2 Logging Strategy

**What to Log:**

| Event | Severity | Reason |
|-------|----------|--------|
| BGP session established | INFO | Normal operation, tracks VM lifecycle |
| BGP session down | WARNING | May indicate VM shutdown or network issue |
| OSPF neighbor down | CRITICAL | Infrastructure failure |
| Route rejected by filter | INFO | Security - tracks injection attempts |
| VRF import/export failure | CRITICAL | Route leaking broken |

**What NOT to Log:**
- BGP keepalives (noise)
- OSPF Hello packets (noise)
- EVPN MAC updates (too frequent)

### 8.3 Troubleshooting Decision Tree

```
Problem: VM cannot reach internet

├─ Can VM ping gateway (fd00:101::fffe)?
│  ├─ NO → EVPN/L2 issue
│  │  ├─ Check: EVPN MAC table on PVE
│  │  ├─ Check: Bridge forwarding table
│  │  └─ Fix: Trigger neighbor learning (ping from PVE)
│  │
│  └─ YES → L3 routing issue
│     ├─ Does VM have default route?
│     │  ├─ NO → BGP issue
│     │  │  ├─ Check: BGP session state on VM
│     │  │  ├─ Check: BGP session on PVE
│     │  │  └─ Fix: Restart FRR, check update-source
│     │  │
│     │  └─ YES → Upstream issue
│     │     ├─ Can PVE reach internet?
│     │     │  ├─ NO → Edge router or upstream issue
│     │     │  └─ YES → Route filtering or next-hop issue
│     │     │     ├─ Check: VM loopback in PVE BGP table
│     │     │     ├─ Check: VM loopback in edge BGP table
│     │     │     └─ Fix: Check route-map filters
```

---

## 9. Future Enhancements

### 9.1 BFD (Bidirectional Forwarding Detection)

**Goal:** Sub-second failure detection (currently 30s BGP hold timer)

**Design:**
```
router bgp 4200001000
  neighbor <peer> bfd
  neighbor <peer> bfd check-control-plane

# BFD session parameters
bfd
  profile infrastructure
    detect-multiplier 3
    receive-interval 300
    transmit-interval 300
```

**Impact:**
- Failure detection: 30s → 0.9s (3 × 300ms)
- Requires: BFD support on edge router
- Complexity: Additional daemon (bfdd)

### 9.2 Segment Routing (SRv6)

**Goal:** Traffic engineering and path control without MPLS

**Use Case:**
- Pin specific tenant traffic to specific uplink
- Implement QoS via path selection
- Enable anycast load balancing with traffic steering

**Design Consideration:**
- Requires kernel 5.10+ (Proxmox 8.0+)
- Requires SRv6-capable edge router
- May be overkill for 3-node cluster

### 9.3 Graceful Restart

**Goal:** Preserve forwarding during FRR upgrades

**Current State:**
```
bgp graceful-restart
# Basic GR enabled, but not tuned
```

**Enhancement:**
```
bgp graceful-restart stalepath-time 300
bgp graceful-restart restart-time 120
bgp graceful-restart select-defer-time 180
```

**Impact:**
- FRR upgrade: 0 packet loss (forwarding preserved)
- Requires: GR support on edge router

### 9.4 BGP Route Aggregation

**Goal:** Reduce routing table size on edge router

**Current State:**
- Every VM loopback advertised as /32 or /128
- Pod CIDRs advertised as per-node /64

**Future Design:**
```
# On PVE
router bgp 4200001000
  address-family ipv6 unicast
    # Aggregate all tenant loopbacks
    aggregate-address fd00:101:fe::/64 summary-only

    # Aggregate all pod CIDRs
    aggregate-address fd00:101:244::/60 summary-only
```

**Tradeoff:**
- Edge router: Smaller routing table (2 routes vs 10+ routes)
- Failover: Less granular (cannot fail over individual VMs)

---

## 10. Security Considerations

### 10.1 Route Injection Prevention

**Threat:** Malicious VM advertises infrastructure routes, hijacks traffic

**Example Attack:**
```
Attacker VM advertises:
  10.255.0.1/32 (pve01 loopback) via BGP

Without filtering:
  → PVE accepts route
  → Other VMs route infrastructure traffic to attacker
  → Man-in-the-middle attack on management traffic
```

**Defense:**
```
route-map IMPORT-VM-ROUTES deny 99
  # Explicit deny-all at end
  # Infrastructure space never matches permit clauses
  # Route rejected, logged
```

**Monitoring:**
```
Alert: frr_bgp_route_rejected{source="vm"} > 0
# Indicates VM attempted to advertise unauthorized route
```

### 10.2 BGP Session Hijacking

**Threat:** Rogue device on tenant VLAN initiates BGP session

**Current Defense:**
```
bgp listen range fd00:101::/64 peer-group VMS
# Only accepts sessions from tenant subnet
# Requires attacker to be on correct VLAN
```

**Enhancement: TCP MD5 Authentication**
```
neighbor VMS password <shared-secret>
# Requires MD5 signature on all BGP packets
# Prevents session establishment without key
```

**Limitation:**
- Requires key distribution to all VMs
- Not currently implemented (operational complexity)

### 10.3 EVPN MAC Spoofing

**Threat:** VM advertises fake MAC/IP binding via EVPN

**Not Possible in Current Design:**
- VMs do not run EVPN (only PVE hosts)
- VMs cannot inject Type 2 routes

**If VMs Had EVPN (Future):**
- Implement MAC-IP binding validation
- Restrict EVPN route advertisements to infrastructure peers only

---

## Appendix A: Configuration Summary

### Infrastructure Layer (Proxmox VE)

**Enabled FRR Daemons:**
- zebra (kernel integration)
- bgpd (BGP routing)
- ospfd (OSPFv2)
- ospf6d (OSPFv3)

**OSPF:**
- Area 0.0.0.0 (single area)
- Advertise infrastructure loopbacks only
- Passive by default, explicit enable on mesh links

**iBGP:**
- AS 4200001000
- Full mesh (3 peers)
- Address families: IPv4 unicast, IPv6 unicast, L2VPN EVPN

**EVPN:**
- advertise-all-vni
- advertise-svi-ip
- Neighbor suppression enabled

**VRF BGP:**
- Dynamic peering via bgp listen range
- remote-as external (unique ASN per VM)
- Route import/export with global table

### Tenant Layer (VM/Talos)

**FRR Configuration:**
- Single BGP neighbor (anycast gateway)
- update-source set to primary IP (critical!)
- Advertise loopback only (connected redistribution)
- Import default route only

**Cilium BGP (Future):**
- Advertise pod CIDRs
- Advertise LoadBalancer VIPs
- Coordinate with host FRR

---

## Appendix B: IP Addressing Reference

| Function | IPv4 | IPv6 |
|----------|------|------|
| Infrastructure Loopbacks | 10.255.0.1-3/32 | fd00:0:0:ffff::1-3/128 |
| Edge Router | 10.255.0.254/32 | fd00:0:0:ffff::fffe/128 |
| Tenant 101 Subnet | 10.101.0.0/24 | fd00:101::/64 |
| Tenant 101 Gateway (Anycast) | 10.101.0.254 | fd00:101::fffe |
| Tenant 101 VM Loopbacks | 10.101.254.0/24 | fd00:101:fe::/64 |
| Tenant 101 Pod CIDR | 10.101.244.0/22 | fd00:101:244::/60 |
| Tenant 101 Service CIDR | 10.101.96.0/24 | fd00:101:96::/108 |
| Tenant 101 LB VIPs | 10.101.240.0/24 | fd00:101:240::/24 |

---

## Appendix C: ASN Reference

| Entity | ASN | Pattern |
|--------|-----|---------|
| Proxmox VE | 4200001000 | Fixed |
| Edge Router | 4200000000 | Fixed |
| Test VMs | 42001<tid><suffix> | tid=tenant, suffix=01-99 |
| Talos CP | 421<tid>01<suffix> | tid=cluster, suffix=11-19 |
| Talos Worker | 421<tid>02<suffix> | tid=cluster, suffix=21-99 |

**Examples:**
- debian-test-1: 4200101006 (tenant 101, VM 06)
- solcp01: 4210101011 (cluster 0101, CP node 11)
- solwk03: 4210101023 (cluster 0101, worker node 23)

---

**END OF DESIGN SPECIFICATION**

This document defines the architecture. Implementation details (exact FRR commands, Ansible playbooks, Terraform modules) should be maintained separately in operational runbooks.
