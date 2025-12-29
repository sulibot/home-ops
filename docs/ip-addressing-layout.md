# IP Addressing Layout (Multi-Tenant / Multi-Cluster)

This document defines how IP space is allocated across:

- Proxmox VE (PVE)
- Underlay fabric
- Tenant / cluster VRFs
- Virtual machines
- Kubernetes clusters
- Services, LoadBalancers, VIPs, and loopbacks

The design prioritizes:

- Deterministic routing
- EVPN compatibility
- Anycast gateways
- Migration-safe identities
- IPv4 / IPv6 symmetry

---

## 1. Global Address Space Allocation

| Scope | IPv4 | IPv6 | Purpose |
|---|---|---|---|
| Management | 10.10.0.0/24 | fd00:10::/64 | PVE UI, SSH, API |
| Underlay fabric | 10.99.0.0/16 | fc00:99::/48 | Routed point-to-point |
| Host loopbacks | 10.255.0.0/16 | fd00:255::/64 | Stable host identity |
| Tenant space | 10.100.0.0/14 | fd00::/48 | Tenants / clusters |

---

## 2. Proxmox VE (PVE) Host Addressing

### Management (non-tenant)

| Host | IPv4 | IPv6 |
|---|---|---|
| pve01 | 10.10.0.1 | fd00:10::1 |
| pve02 | 10.10.0.2 | fd00:10::2 |
| pve03 | 10.10.0.3 | fd00:10::3 |

### Host Loopback / Fabric Identity

| Host | IPv4 (/32) | IPv6 (/128) |
|---|---|---|
| pve01 | 10.255.0.1 | fd00:255::1 |
| pve02 | 10.255.0.2 | fd00:255::2 |
| pve03 | 10.255.0.3 | fd00:255::3 |

---

## 3. Tenant / Cluster Addressing Pattern

Each tenant or cluster is identified by an ID (e.g. 101).

| Purpose | IPv4 | IPv6 |
|---|---|---|
| VM data plane | 10.<T>.0.0/24 | fd00:<T>::/64 |
| Anycast gateway | 10.<T>.0.254 | fd00:<T>::fffe |
| Host identities | 10.<T>.255.0/24 | fd00:<T>:ff::/64 |
| VM loopbacks | 10.<T>.254.0/24 | fd00:<T>:fe::/64 |

---

## 4. Tenant 101 Example

| Purpose | IPv4 | IPv6 |
|---|---|---|
| VM subnet | 10.101.0.0/24 | fd00:101::/64 |
| Anycast gateway | 10.101.0.254 | fd00:101::fffe |
| Host identities | 10.101.255.0/24 | fd00:101:ff::/64 |
| VM loopbacks | 10.101.254.0/24 | fd00:101:fe::/64 |

---

## 5. Kubernetes (Tenant 101)

| Purpose | IPv4 | IPv6 |
|---|---|---|
| Pods | 10.101.244.0/22 | fd00:101:244::/60 |
| Services | 10.101.96.0/24 | fd00:101:96::/108 |
| LoadBalancers | 10.101.27.0/24 | fd00:101:1b::/112 |

---

## 6. Mental Model

- Anycast → forwarding abstraction  
- Host ff → PVE identity inside tenant VRF  
- VM subnet → workload data plane  
- VM fe → workload identity  
- Loopbacks → routing identity
