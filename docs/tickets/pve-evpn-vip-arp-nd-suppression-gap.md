# Ticket: cluster-101 kube-apiserver VIP unreachable cross-node after EVPN network event

- Status: Open (investigation ongoing - initial root-cause theory was wrong, see below)
- Priority: High
- Area: PVE SDN, FRR, EVPN, cluster-101 networking
- Created: 2026-07-13

## Summary

Surfaced during MTU/exit-node-failover testing (see
`docs/tickets/pve-frr-power-event-20260712.md`): the cluster-101
kube-apiserver VIP (`fd00:101::10`, a Talos-native control-plane VIP) became
unreachable from pve01/pve02 and did not self-recover. The cluster itself was
never actually down - all 6 nodes stayed `Ready` and reachable via their
individual node IPs the whole time - only the convenience VIP path broke.

## Root Cause: still open - one theory ruled out

**Ruled out: EVPN Type-5 (IP-prefix) export.** Initial diagnosis assumed the
VRF-scoped BGP instance (`router bgp <AS> vrf vrf_evpnz1`) was missing
`advertise ipv4/ipv6 unicast` and that this was blocking Type-5 export of the
VIP route. Tested this directly: added the `advertise` statements under a new
`address-family l2vpn evpn` block on the vrf's BGP instance on all three
nodes. **Result: no change, still zero Type-5 routes anywhere
(`show bgp l2vpn evpn route type prefix` stayed empty on all nodes).**

Root cause of the *test's* null result: `show bgp l2vpn evpn vni` shows
`Number of L3 VNIs: 0` on every node. This fabric has **never** used
symmetric-IRB/Type-5 routing - `vrf_vxlan = 4096` (the zone's VXLAN ID) is
used purely as an L2 VNI whose tenant happens to be `vrf_evpnz1`, not a real
L3VNI. `advertise ipv4/ipv6 unicast` has nothing to encapsulate without an
L3VNI mapping, so it's a no-op in this design. This fabric has run correctly
for 127+ days on Type-2 (MAC/IP) EVPN routes and ARP/ND suppression alone -
Type-5 was never part of it, and pursuing it further would mean introducing
symmetric-IRB routing as new architecture, not fixing a regression.
**The advertise-statement change was reverted on all three nodes** (`no
advertise ipv4 unicast` / `no advertise ipv6 unicast`, then `write memory`),
confirmed to match the original config exactly; no ansible/template changes
were kept either.

## What's actually still true (from the original investigation)

- The VIP was confirmed bound and answering locally on its holder (`solcp03`,
  via `talosctl get addressstatuses` showing `ens18/fd00:101::10/128`), and
  reachable from pve03 (the VIP's own node) with 0% loss.
- It was absent from every node's EVPN Type-2 (MAC/IP) table too - not just
  Type-5. Regular guest addresses (e.g. `fd00:101::13`) DO show up correctly
  as Type-2/ARP-suppressed entries cross-node, so the general Type-2
  mechanism works; this VIP specifically didn't.
- pve01/pve02 could not resolve it via ND: with ARP/ND suppression enabled,
  an unknown destination gets an immediate synthetic "Address unreachable"
  from the local gateway rather than a flooded NS, so nothing triggers
  (re)learning once no EVPN route exists for it - a chicken-and-egg
  condition.
- A local round-trip ping sourced from pve03's own gateway to the VIP
  succeeded (proving the dataplane path works), but did not produce a new
  Type-2 route or ND cache entry afterward - meaning whatever Talos's VIP
  failover does to claim the address doesn't produce a
  snoopable/re-triggerable NS/NA exchange that FRR's ARP/ND suppression
  picks up.

## Current best theory (untested)

Talos's control-plane VIP mechanism likely sends its gratuitous/unsolicited
Neighbor Advertisement exactly once, at claim time. If PVE's ARP/ND
suppression snooping missed that specific packet (plausible given the
SDN/FRR reloads happening around the same time during today's testing), and
if unicast NA replies to a later NS aren't visible to the snooping path
(common in bridge/VXLAN NDP-snooping implementations - the snoop only
catches multicast solicitations and their responses, not always unicast
follow-ups), the route can be permanently stuck until something re-triggers
the *original* gratuitous NA - e.g. Talos re-electing/re-claiming the VIP.

## Not chased further live

Stopped here given the risk of continued production EVPN experimentation
without a clear resolution path, and because the underlying theory (Type-5)
already turned out to be wrong once. Cluster itself was never impacted -
only the convenience VIP path was down.

## Next steps (for whoever picks this up)

- [ ] Confirm the theory: check whether `fd00:101::10` is still unreachable
      cross-node right now, or whether it self-healed after a later Talos VIP
      re-election.
- [ ] If still broken, try forcing a fresh gratuitous NA cleanly (e.g. a
      controlled Talos control-plane leadership transfer or a VIP-holder
      reboot of just `solcp03`), then immediately check
      `show bgp l2vpn evpn route` / ND cache on pve01/pve02 for the VIP.
      Confirm it resolves before assuming this is the fix.
- [ ] If that works, the durable fix is likely on the Talos/kube-vip-style
      config side (send periodic/repeated gratuitous NAs, not just once), not
      on the FRR/EVPN side - avoid further FRR config changes for this until
      that's confirmed.
- [ ] Do not reintroduce `advertise ipv4/ipv6 unicast` or otherwise pursue
      Type-5/symmetric-IRB for this fabric without a deliberate, separate
      architecture decision - it's a bigger change than this ticket's scope
      and isn't needed for anything else currently running.

## Related Files

- `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`
- `docs/tickets/pve-frr-power-event-20260712.md`
