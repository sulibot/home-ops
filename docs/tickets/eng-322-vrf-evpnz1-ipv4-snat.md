# ENG-322: Restore native Proxmox SDN exit-node SNAT for vrf_evpnz1 IPv4 egress

## Status: RESOLVED (see Linear ENG-322, closed). All known gaps fixed and
verified via real production traffic (Flux reconciliation, cloudflare-tunnel).
See "Final root cause" section below for the actual fix. The
`exitnodes-primary` gap that caused the double-encapsulation symptom earlier
in this investigation is tracked separately as ongoing tech debt in ENG-324
(no upstream Proxmox/FRR fix exists for it - workaround is durable but not a
first-class supported feature).

## Follow-on work built on this fix (all resolved, tracked separately)

This ticket's conntrack-zone/NAT44 mechanism (`evpn-runtime-guard.j2`,
`xvrf_ips.j2`, `interfaces.pve.j2`) turned out to need several more rounds of
fixes as new traffic patterns exercised it. Not re-documented here in full -
see each Linear ticket for its own root-cause writeup:

- **ENG-359/360/361** - IPv6 NAT66 egress for LXCs/VMs, same-node crossing for
  the PVE mgmt subnet, tenant-200 IPv6 gap.
- **ENG-362** - tenant egress reply packets lost on the direct BGP-leaked
  route (root cause: a stray manually-added IPv6 `table local` route, not a
  design flaw).
- **ENG-363** - pve01-hosted VMs losing TLS handshakes to external hosts
  (wrong-source-port replies); fixed by a full host reboot, mechanism never
  fully explained.
- **ENG-364** - `ceph-mds` cache overrunning its configured limit caused an
  OOM-kill of a pve02-hosted VM; mitigated with dedicated Optane-backed swap
  on pve01/pve02 (`ansible/pve/roles/optane_swap/`).
- **ENG-366** - the IPv6 equivalent of this ticket's own `10.255.0.0/24`
  RETURN exemption was never added for the PVE mgmt network
  (`fd00:10::/64`), so tenant-subnet NAT66 was masquerading legitimately
  local-routed mgmt traffic. Fixed by mirroring the same RETURN-exemption
  pattern for IPv6.

Also worth noting: `ansible/pve/playbooks/20-network.yml` now rolls out
serially with a Ceph mon-quorum health gate between nodes by default (see
ENG-363's postmortem) - any future change to these templates should deploy
through that playbook rather than by hand across all 3 nodes at once.

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

## Remaining known gap - RESOLVED, root cause split into ENG-324

**Full TLS sessions to real external hosts (github.com et al) were
failing**, even after the MSS clamp fix. Packet capture showed plain TCP
connects succeeding, but for TLS handshakes the masqueraded flow's reply
traffic triggered a TCP RST sent by the *node's own kernel* (source = node
IP, not pod IP), interleaved with legitimate reply data on the same live
connection - two divergent conntrack states for one flow. The Cilium eBPF
hypothesis originally written here was ruled out (a `hostNetwork: true`
test pod, bypassing Cilium's pod networking entirely, failed identically).

Actual root cause: Proxmox's native SDN generator doesn't honor
`exitnodes-primary` (configured in `zones.cfg` but inert), so every exit
node self-originates a competing default route into L2VPN EVPN at
identical BGP local-preference. A hand-rolled static cross-VRF route
(`interfaces.pve.j2`, since removed) was masking the resulting BGP
best-path ambiguity but itself caused the VRF-crossing double-POSTROUTING/
conntrack bug producing the RSTs above. Fixed via a route-map local-
preference override in the frr role. This is real, currently-unfixed
upstream Proxmox/FRR tech debt - split out into its own ticket, **Linear
ENG-324**, since it isn't tracked by any existing Proxmox Bugzilla or FRR
issue. See ENG-324 for the full evidence trail and the workaround's exact
diff.

This was blocking Flux's GitRepository/HelmRepository sources and
`cloudflare-tunnel`. **Correction**: this fix alone did not actually resolve
either - see "Final root cause" below for what did. The exitnodes-primary
fix was still worth doing (real, separate bug, now tracked in ENG-324) but
it wasn't the source of the TLS/DNS symptom.

## Final root cause (found after the exitnodes-primary fix didn't fully
resolve the symptom)

SNAT'd tenant reply traffic must cross from the default VRF (where
`vmbr0.10`'s un-SNAT happens via conntrack) back into `vrf_evpnz1` to reach
the pod/VM. This crossing happens via the `xvrf_evpnz1`/`xvrfp_evpnz1` veth
pair, using explicit native-generated static routes (confirmed live in
`/etc/frr/frr.conf`: `ip route 10.100-103.0.0/24 10.255.255.2
xvrf_evpnz1`, not present in any ansible template). This VRF crossing hits
a real Linux kernel double-POSTROUTING/conntrack bug for NAT'd flows
crossing a VRF boundary via a veth pair - confirmed via packet capture
showing TCP RSTs sourced from the pre-NAT tenant address (e.g.
`10.101.0.21`), interleaved with legitimate reply data on the same live
TLS connection.

Two theories were tested and ruled out before finding this (both
individually and combined): MTU mismatch (jumbo internal fabric vs 1500
real uplink) and Cilium's own per-route MTU handling
(cilium/cilium#41478, a real but ultimately irrelevant matching upstream
bug - coincidental resemblance, not the actual cause).

**Fix**: explicit conntrack zone isolation for both ends of the xvrf
crossing:
```
iptables -t raw -I PREROUTING -i xvrf_evpnz1 -j CT --zone 5
iptables -t raw -I PREROUTING -i xvrfp_evpnz1 -j CT --zone 5
```
This is the correct version of an idea already present but dead in this
cluster - Proxmox natively generates an identical-looking `CT --zone 1`
rule per vnet, but targeting `fwbr+` (per-VM firewall bridges), which don't
exist in this topology (VMs connect directly to vnet bridges via tap
interfaces). That native rule has always had 0 hits. Targeting the actual
crossing point instead of the dead `fwbr+` interface is what makes it work.

Persisted to `ansible/pve/roles/interfaces/templates/xvrf_ips.j2` as
`post-up`/`post-down` hooks on both xvrf interface stanzas, applied via
`playbooks/20-network.yml` to pve01/02/03, confirmed durable (survives
`ifreload`).

**Verified via real production signal**: Flux's GitRepository went from
persistent `TLS handshake timeout` failures to `True - stored artifact for
revision ...` immediately after applying to all 3 PVE hosts.
`cloudflare-tunnel` both replicas recovered (`1/1 Running`, no longer
crash-looping).

## Follow-up worth tracking separately

Whether to eventually migrate off the custom ansible FRR template back to
Proxmox's native SDN-generated config entirely, now that we know the two
have diverged. Not in scope here.
