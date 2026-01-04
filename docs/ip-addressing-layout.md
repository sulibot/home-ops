# IP Addressing & Identity Architecture  
**Multi-Tenant / Multi-Cluster Datacenter Fabric**

**Author:** Network Architecture  
**Audience:** Network Engineering / Platform Infrastructure  
**Intent:** Define a stable, scalable, and review-defensible IP addressing and identity model suitable for routed datacenter fabrics, EVPN, and Kubernetes.

---

## 0. Architectural Premise

This design assumes:

- A routed underlay fabric
- Control-plane driven forwarding (IGP + BGP / EVPN)
- Anycast gateways
- VM and workload mobility
- Dual-stack IPv4 / IPv6 with parity in semantics

The primary goal is **operational clarity and stability**, not novelty.

> Addresses encode *role*, not topology.  
> Topology is expressed by routing, not numbering.

---

## 1. Design Principles

1. **Identity and forwarding are separate concerns**
   - Loopbacks identify nodes
   - Interfaces forward traffic

2. **Address meaning must be obvious without documentation**
   - Common enterprise conventions are preferred
   - Numbers are boring on purpose

3. **Migration must not require renumbering**
   - Hosts and workloads retain identity independent of location

4. **IPv4 and IPv6 must express the same intent**
   - Dual-stack is symmetric, not bolted on

---

## 2. Global Address Space Allocation

| Scope | IPv4 | IPv6 | Rationale |
|------|------|------|-----------|
| Management | `10.10.0.0/24` | `fd00:10::/64` | Low, well-known block; non-tenant |
| Underlay Fabric | `10.99.0.0/16` | `fc00:99::/48` | Transport only; no workloads |
| Infrastructure Loopbacks | `10.255.0.0/16` | `fd00:0:0:ffff::/64` | Widely recognized infra convention |
| Tenant / VRF Space | `10.100.0.0/14` | `fd00::/48` | Large contiguous tenant pool |

**Notes**

- `10.255/16` is reserved exclusively for routing identity
- IPv6 ULAs are structured for readability, not randomness
- Management and underlay space never leak into tenant VRFs

---

## 3. Proxmox VE Host Addressing

### 3.1 Management Network (Non-Tenant)

| Host | IPv4 | IPv6 |
|------|------|------|
| pve01 | `10.10.0.1` | `fd00:10::1` |
| pve02 | `10.10.0.2` | `fd00:10::2` |
| pve03 | `10.10.0.3` | `fd00:10::3` |

**Purpose**

- Host access only (UI, SSH, API)
- No tenant traffic
- No anycast semantics

---

### 3.2 Infrastructure Loopback (Fabric Identity)

| Host | IPv4 (/32) | IPv6 (/128) |
|------|------------|-------------|
| pve01 | `10.255.0.1` | `fd00:0:0:ffff::1` |
| pve02 | `10.255.0.2` | `fd00:0:0:ffff::2` |
| pve03 | `10.255.0.3` | `fd00:0:0:ffff::3` |

**Usage**

- Router-ID
- BGP next-hop
- EVPN VTEP source
- Control-plane reachability

> These addresses never change.  
> Physical interfaces are irrelevant to identity.

---

## 4. Tenant / Cluster Addressing Model

Each tenant or cluster is assigned a **Tenant ID (TID)**.  
The TID is a logical identifier, not a VLAN or physical construct.

### Per-Tenant Allocation Pattern

Each tenant or cluster is assigned a **Tenant ID (TID)** which structures all addressing within that tenant's VRF.

| Function | IPv4 | IPv6 | Purpose |
|---------|------|------|---------|
| VM Data Plane | `10.<TID>.0.0/24` | `fd00:<TID>::/64` | Primary VM/workload network; hosts 1-253 available |
| Anycast Gateway | `10.<TID>.0.254` | `fd00:<TID>::fffe` | Shared first-hop gateway; present on all hypervisors |
| VM Loopbacks | `10.<TID>.254.0/24` | `fd00:<TID>:fe::/64` | Routing identity for workloads; /32 and /128 allocations |

**Addressing Semantics**

- **Data Plane** (`10.<TID>.0.0/24`): Traditional subnet for VM interfaces
  - Gateway always at `.254` / `::fffe` (enterprise convention)
  - Usable range: `.1` through `.253` / `::1` through `::fffd`
  - DHCP pools typically `.10-.250` to preserve static IP space

- **Anycast Gateway** (`10.<TID>.0.254`): Layer-3 gateway address
  - Configured identically on all hypervisors in the VRF
  - VMs see stable gateway regardless of physical location
  - Enables VM mobility without renumbering

- **VM Loopbacks** (`10.<TID>.254.0/24`): Control-plane identity for workloads
  - Used for BGP peering, service endpoints, stable identity
  - Allocated as /32 (IPv4) and /128 (IPv6) host routes
  - Advertised via BGP; survives VM migration
  - Example: Kubernetes node loopbacks, Talos system addresses

**Design Notes**

- All ranges are routable within the tenant VRF
- Gateway convention (`.254` / `::fffe`) is globally consistent
- Loopback space (`.254.x` / `:fe::`) intentionally adjacent to gateway for clarity
- No NAT required; all addressing is routed end-to-end

---

## 5. Example: Tenant 101

| Function | IPv4 | IPv6 |
|---------|------|------|
| VM Data Plane | `10.101.0.0/24` | `fd00:101::/64` |
| Anycast Gateway | `10.101.0.254` | `fd00:101::fffe` |
| VM Loopbacks | `10.101.254.0/24` | `fd00:101:fe::/64` |

**Operational Implications**

- Any PVE host can forward for the tenant (anycast gateway)
- Routing determines the active path (BGP best path selection)
- VM mobility is transparent to the network (loopbacks remain stable)
- Example VM addresses: `10.101.0.1-253` with gateway at `.254`
- Example VM loopbacks: `10.101.254.11/32`, `10.101.254.21/32`, etc.

---

## 6. Kubernetes Addressing (Within Tenant VRF)

Kubernetes ranges are **subsets of tenant space** and are routed, not NATed.

| Function | IPv4 | IPv6 | Rationale |
|---------|------|------|-----------|
| Pod CIDR | `10.101.244.0/22` | `fd00:101:244::/60` | Large, routable workload space |
| Service CIDR | `10.101.96.0/24` | `fd00:101:96::/108` | Virtual IPs only |
| LoadBalancer VIP Pool | `10.101.240.0/24` | `fd00:101:fffe::/112` | High-range, clearly reserved |

**Notes**

- Pod CIDRs are routable and advertised via BGP
- Service CIDRs are virtual and never routed externally
- LoadBalancer VIPs are explicitly reserved and advertised

---

## 7. Address Semantics Summary

| Role | IPv4 Pattern | IPv6 Pattern |
|-----|--------------|--------------|
| Infrastructure loopback | `10.255.x.x/32` | `fd00:…:ffff::/128` |
| Anycast gateway | `.254` | `::fffe` |
| Host identity | `.255.x` | `:ff::/64` |
| VM loopback | `.254.x` | `:fe::/64` |
| Workload subnet | `.0.0/24` | `::/64` |
| LB VIP pool | High `/24` | `fffe::/112` |

---

## 8. Operational Guidance

- Do not encode topology in addressing
- Do not repurpose reserved ranges
- Do not leak management or underlay space into tenant VRFs
- Treat loopbacks as control-plane assets, not interfaces

> If an address needs explanation, the design has failed.

---

## 9. Closing Statement

This addressing plan is intentionally conservative.

It aligns with:

- Long-standing enterprise IPv4 practices
- Modern IPv6 role-marker usage
- EVPN and BGP operational reality
- Kubernetes without NAT or overlays

The result is a fabric that is:

- Predictable
- Debuggable
- Migration-safe
- Understandable by any experienced network engineer

That is the bar.
