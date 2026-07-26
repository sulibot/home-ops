# ENG-322: Restore native Proxmox SDN exit-node SNAT for vrf_evpnz1 IPv4 egress

## Status: In progress (see Linear ENG-322)

## Design goals (network engineer framing)

**Fabric roles:**
- `vrf_evpnz1` (EVPN/VXLAN, BGP ASN 4200001000) is the tenant data plane —
  currently hosting `vnet101` (K8s cluster-101, BGP-speaking,
  dynamic-neighbor-enabled) and reserved `vnet100`/`102`/`103` for future
  durable/tenant workloads.
- `vnet200` is out-of-band infrastructure (NAT64 gateway, other one-off
  utility VMs/LXCs) - not part of the tenant EVPN fabric, not BGP-speaking by
  design.
- The router (RouterOS) is the L3 edge/policy boundary - the single
  enforcement point for anything crossing from the fabric to the public
  internet.

**Non-negotiable requirements:**
1. **VM/workload mobility**: any node can host any workload at any time;
   nothing may be pinned to a specific PVE host for correctness (rules out
   primary/backup exit-node designs where non-primary nodes depend on the
   primary).
2. **No double encapsulation**: egress traffic must not take an extra VXLAN
   hop to a remote exit node before breaking out - each host must be able to
   route/NAT its own local traffic directly.
3. **Prefer standard, community/vendor-supported patterns over custom
   automation**, even at some cost to "purity" - this is the primary
   tiebreaker.
4. **IPv6-first, NAT-free where legitimate**: real GUA addressing for
   pod/VM egress is the preferred default and already works end-to-end; this
   is a deliberate architecture choice, not an accident, and its tradeoff
   (router/firewall as sole enforcement point, no NAT-implied ACL) is
   accepted knowingly.
5. **IPv4 is the exception path**, needed only for destinations without
   AAAA records; it should get the smallest footprint necessary, not parity
   with IPv6.
6. **BGP/dynamic routing is scoped deliberately per-tenant**
   (`bgp_dynamic_neighbors` true only for vnet101) - used where it teaches
   something or is operationally necessary, not applied fabric-wide by
   default.
7. **Simplicity is a secondary tiebreaker**, applied only after the above
   are satisfied.

## Current state / root cause

Proxmox's native SDN exit-node mechanism is already configured in
`/etc/pve/sdn/zones.cfg`:

```
evpn: evpnz1
    exitnodes pve01,pve03,pve02
    exitnodes-local-routing 1
    exitnodes-primary pve01
```

`exitnodes-local-routing 1` with all three hosts listed is architecturally
exactly what satisfies requirements (1) and (2) - each host breaks out its
own local vrf_evpnz1 traffic directly, no tunnel-to-remote-exit-node hop.

However, this is currently inert. At some point (likely the 2026-07-13
refactor referenced in the ansible README, moving off `lae.proxmox-legacy`),
FRR management moved from Proxmox's native SDN-generated config to a fully
custom ansible template (`ansible/pve/roles/frr/templates/frr-pve.conf.j2` -
confirmed live `/etc/frr/frr.conf` is ansible-managed via
`.frr.conf.ansible-hash`, with `/etc/frr/frr.conf.sdn-generated-20260712`
sitting unused as a dated backup). The custom template replicates routing
but never carried over the SNAT half of exit-node behavior.

Result: `vrf_evpnz1` has real routing to the internet (a stale ad-hoc
`ip route` onlink hack, added as a live patch during an earlier incident)
but **no NAT rule anywhere** on any PVE host. IPv6 GUA egress works fine (no
NAT needed). IPv4 egress is completely broken - confirmed cluster-wide (all
3 PVE hosts fail `nc` to 1.1.1.1 and to GitHub's IPv4), which was actively
blocking Flux's GitRepository source (`dial tcp 20.29.134.23:443: i/o
timeout` reaching github.com) and a couple of IPv4-only external
dependencies (plex.tv, no AAAA record).

An adjacent NAT64/DNS64 path exists (`ansible/nat64/`, a dedicated Jool
gateway VM) but DNS64 synthesis isn't actually happening - queried the
cluster's configured resolvers directly for an IPv4-only domain and got no
synthesized AAAA back. Not pursuing that path further for now per
requirement 5 (smallest footprint, not parity).

## Decision

Add IPv4-only SNAT/MASQUERADE to the existing ansible-managed FRR/networking
setup (not a full migration back to native SDN-generated FRR - too large a
change to do safely right now), scoped to the tenant IPv4 subnet range
(10.100.0.0/22, covering vnet100-103), applied identically on all three PVE
hosts to match `exitnodes-local-routing` semantics. Remove the stale onlink
route hack once confirmed working. This intentionally does not touch IPv6
(already working, no NAT desired there).

## Follow-up worth tracking separately

Whether to eventually migrate off the custom ansible FRR template back to
Proxmox's native SDN-generated config entirely, now that we know the two
have diverged. Not in scope here - flagged as a larger, riskier change
requiring dedicated review.
