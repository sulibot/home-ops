# ENG-322: Restore native Proxmox SDN exit-node SNAT for vrf_evpnz1 IPv4 egress

## Status: In progress (see Linear ENG-322) - core DNS/image-pull issue
fixed, TLS-to-external-hosts gap remains open

## Design goals (network engineer framing)

**Fabric roles:**
- `vrf_evpnz1` (EVPN/VXLAN, BGP ASN 4200001000) is the tenant data plane -
  currently hosting `vnet101` (K8s cluster-101, BGP-speaking,
  dynamic-neighbor-enabled) and reserved `vnet100`/`102`/`103` for future
  durable/tenant workloads.
- `vnet200` is out-of-band infrastructure (NAT64 gateway, other one-off
  utility VMs/LXCs) - not part of the tenant EVPN fabric, not BGP-speaking by
  design.
- The router (RouterOS) is the L3 edge/policy boundary - the single
  enforcement point for anything crossing from the fabric to the public
  internet.
- **The network is IPv6-first by design.** Real GUA addressing for pod/VM
  egress is the default and already works end-to-end; IPv4 is deliberately
  the exception path.

**Non-negotiable requirements:**
1. **VM/workload mobility**: any node can host any workload at any time;
   nothing may be pinned to a specific PVE host for correctness.
2. **No double encapsulation**: egress traffic must not take an extra VXLAN
   hop to a remote exit node before breaking out - each host must be able to
   route/NAT its own local traffic directly. (Confirmed satisfiable by
   Proxmox's native `exitnodes-local-routing`.)
3. **Prefer standard, community/vendor-supported patterns over custom
   automation**, even at some cost to "purity" - primary tiebreaker
   (enterprise-DC-style patterns preferred when otherwise equal).
4. **IPv6-first, NAT-free where legitimate** - accepted tradeoff:
   router/firewall is the sole enforcement point, no NAT-implied ACL.
5. **IPv4 is the exception path**, smallest footprint necessary, not parity
   with IPv6.
6. **BGP/dynamic routing is scoped deliberately per-tenant**
   (`bgp_dynamic_neighbors` true only for vnet101).
7. **Simplicity is a secondary tiebreaker**, applied only after the above
   are satisfied.

## Current state / root cause

Proxmox's native SDN exit-node mechanism is already configured in
`/etc/pve/sdn/zones.cfg` (`exitnodes pve01,pve03,pve02`,
`exitnodes-local-routing 1`) but is currently inert - FRR management moved
to a hand-built ansible template during an earlier refactor and the SNAT
half of that native behavior was never carried over.

## Work completed

1. Added IPv4-only NAT/masquerade for tenant subnets (`10.100.0.0/14` -
   corrected from an initially-wrong `/22`; these subnets vary in the
   *second* octet, not the third) on all 3 PVE hosts, matching
   `exitnodes-local-routing` semantics
   (`ansible/common/roles/firewall/templates/nftables.conf.j2`).
2. Made the underlying default route for `vrf_evpnz1` durable
   (`ansible/pve/roles/interfaces/templates/interfaces.pve.j2`) - it only
   existed live before; a host reboot would have silently lost egress
   entirely. Note: the "proper" BGP-learned recursive default route shows
   Selected/Installed in FRR but does **not** actually forward traffic -
   tested live, reverted to the working static route, root cause not
   understood, worth separate investigation.
3. Fixed 2 unrelated pre-existing ansible bugs hit along the way:
   `cluster.fw.j2` had drifted from live state and was about to strip 2
   live ACCEPT rules; the firewall-reload task used
   `ansible.builtin.command` with a shell `&&` chain that silently never
   worked, switched to `ansible.builtin.shell`.
4. Found and fixed a masquerade side-effect breaking the cluster's IPv4 DNS
   resolver: `10.255.0.0/24` (OSPF-external/E1 routes from RouterOS,
   includes DNS at `10.255.0.53`) was being caught by the general
   masquerade rule, breaking its direct return path and causing real
   image-pull failures cluster-wide. Fixed with an explicit `return` before
   the general rule.
5. Extended the pre-existing MSS-clamp rule
   (`docs/tickets/pve-frr-power-event-20260712.md`) to also cover
   `vmbr0.10` (the new NAT path's actual egress interface, which the
   original rule - scoped to plain `vmbr0` - never touched).

## Remaining known gap (not resolved)

**Full TLS sessions to real external hosts (github.com et al) still fail**,
even after the MSS clamp fix. Packet capture shows plain TCP connects
succeed, but for TLS handshakes the masqueraded flow's reply traffic
triggers a TCP RST sent by the *node's own kernel* (source = node IP, not
pod IP) - consistent with Cilium's eBPF datapath not correctly intercepting
reply packets that were NAT'd an extra hop away (at the PVE host, outside
the node), rather than the more typical single-hop node-IP masquerade
Cilium expects.

This is currently blocking Flux's GitRepository/HelmRepository sources
(`net/http: TLS handshake timeout` reaching github.com and other chart
repos) - GitOps reconciliation for *new* commits is stalled until this is
fixed, though the cluster itself and all currently-running workloads are
fully healthy and unaffected.

Needs focused, unhurried investigation - likely need to trace the exact
Cilium eBPF hook chain for egress-masqueraded reply traffic, or consider
whether Cilium's own egress gateway feature can absorb this instead of
doing NAT an extra hop out at the PVE layer.

## Follow-up worth tracking separately

Whether to eventually migrate off the custom ansible FRR template back to
Proxmox's native SDN-generated config entirely, now that we know the two
have diverged. Not in scope here.
