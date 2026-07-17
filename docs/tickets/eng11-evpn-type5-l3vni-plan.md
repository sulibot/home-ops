# Plan: wire up EVPN Type-5/symmetric-IRB via the existing L3VNI

Written 2026-07-14, planning-only (no live changes made). Follow-up to
ENG-7/ENG-10 - the four workarounds tried there all hit the same
architectural wall (VRF-leaked/point-to-point routes can't resolve
link-local next-hops across nodes). This is the actual fix.

## The gap, precisely

- `terraform/infra/modules/proxmox_sdn/variables.tf` describes `vrf_vxlan`
  (currently `4096`, live) as **"VRF VXLAN ID for Layer 3 routing
  interconnect"** - that's L3VNI language, already provisioned at the PVE
  SDN zone level.
- Proxmox's own SDN docs: "An EVPN zone represents a routing table
  instance (IP-VRF)... associated with a VXLAN VNI referred to as L3VNI."
  EVPN zones are supposed to have one.
- But the live fabric was checked during the original VIP investigation
  (docs/tickets/pve-evpn-vip-arp-nd-suppression-gap.md) and showed
  `show bgp l2vpn evpn vni`: **Number of L3 VNIs: 0** on every node.
- `ansible/pve/roles/frr/templates/frr-pve.conf.j2`'s VRF BGP instance
  (`router bgp {{ LOCAL_AS }} vrf {{ VRF_NAME }}`, line ~496) has
  `address-family ipv4 unicast` and `address-family ipv6 unicast` blocks
  only - **no `address-family l2vpn evpn` block at all**. That's the
  missing piece: the VRF is never told which VNI is its L3VNI, so `vni
  4096` is just an L2 VNI shared by tenant vnets, never bound to the VRF
  for routing purposes.

This matches the earlier incident's own conclusion almost exactly, but
with one important correction: last time, `advertise ipv4/ipv6 unicast`
was added under the VRF's `l2vpn evpn` AF *without* first binding the
VRF to an L3VNI via `vni <id>` - so there was nothing for it to advertise
into. That's very likely why it no-op'd, not because Type-5 is
unsupported.

## Proposed FRR config change (untested, needs a lab/single-node trial)

Add to the VRF BGP instance in `frr-pve.conf.j2`:

```
router bgp {{ LOCAL_AS }} vrf {{ VRF_NAME }}
 ...
 address-family l2vpn evpn
  vni {{ vrf_vxlan_id }}
  advertise ipv4 unicast
  advertise ipv6 unicast
 exit-address-family
exit
```

`vrf_vxlan_id` would come from `network_facts.sdn_vrf_vxlan` (already
piped from Terraform via `ansible/network-facts.json`, from ENG-9's
work - no new plumbing needed, the value's already flowing into ansible).

## Real open questions before touching anything live

1. **Does PVE's SDN zone regeneration itself ever write a `vni <id>`
   binding under the VRF instance, or is this 100% hand-authored FRR
   config territory (like everything else in this template)?** If PVE's
   SDN system doesn't know about L3VNI at all in its own generated output,
   this is purely our template's job and safe to add via the established
   `frr.conf.local` merge pattern (survives SDN regeneration, same as the
   underlay). If PVE *partially* manages this, need to understand the
   interaction before adding a conflicting hand-written block.
2. **Does adding `vni 4096` under the VRF conflict with `4096` already
   being used as every tenant vnet's shared L2 VNI** (`vxlan_id = 10000 +
   tenant_id` per `sdn-vnets.hcl` - wait, that's actually a *different*
   number per tenant; `vrf_vxlan=4096` is the *zone's* VNI, separate from
   each vnet's own `vxlan_id`). Need to confirm there's no collision
   between the zone-level L3VNI and any per-tenant L2 VNI before assuming
   they can coexist - this is the kind of detail that's caused real
   incidents in this fabric before (the FRR power-event ticket has
   multiple examples of exactly this class of oversight).
3. **What actually changes for existing Type-2 traffic once Type-5 is
   live?** Symmetric IRB routes inter-subnet traffic through the L3VNI
   instead of bridging it through the L2 VNI. Existing pod-to-pod/VM
   traffic within a tenant (same subnet) should be unaffected (still pure
   L2/Type-2), but anything crossing between the VRF and global table
   might start preferring the new Type-5 path over the existing
   VRF-leak-via-iBGP path - need to verify this doesn't change behavior
   for the pod-CIDR routes that currently work, not just add a new
   capability alongside them.

## Suggested validation approach (not attempted, for next session)

1. Add the `address-family l2vpn evpn` VRF block to the template, but
   **do not roll out to all 3 nodes at once** - this touches the exact
   fabric that's already had incidents. Test the rendered config with
   `vtysh -f <file> -C` (syntax check only, no live apply) first.
2. Apply to **one node only** via `vtysh -c 'configure terminal'` live
   session first (same pattern used successfully for the
   `RM_GLOBAL_TO_VRF_V6 permit 35` fix in ENG-7), not a full `ifreload`/
   ansible push, so it's trivially reversible with `no vni {{ id }}` if
   something looks wrong.
3. Check `show bgp l2vpn evpn vni` on that node - expect to see the L3VNI
   now listed (currently shows 0 everywhere).
4. Advertise a throwaway test route (not the real kube-apiserver VIP) and
   check whether it now installs `Status: Installed` on the *other* two
   nodes without the VRF-leak recursion problem - this is the actual
   proof this approach works, mirroring the same test methodology used
   for the (failed) `peer101` attempt.
5. Only after that's confirmed clean: roll to all 3 nodes, then resume
   the kube-vip BGP mode plan (ENG-10) using this now-working mechanism
   instead of any point-to-point addressing trick.

## Why this is worth doing properly rather than live tonight

Every workaround attempted live in ENG-10 touched the exact fabric that
had a real production incident before this session even started
(docs/tickets/pve-frr-power-event-20260712.md). Adding a genuinely new
BGP address-family to the VRF instance is a bigger, more structural
change than any of those - it deserves a single-node trial with a clean
rollback path and someone actively watching, not a rushed multi-node
rollout at the end of an already-long session with multiple incidents
already on the board.

## Related

- ENG-7 (original VIP incident, Type-5 first ruled out here)
- ENG-10 (four workarounds tried, all failed - this plan is the answer to
  "what would actually fix it")
- `ansible/pve/roles/frr/templates/frr-pve.conf.j2` (where the change
  goes)
- `terraform/infra/modules/proxmox_sdn/variables.tf` (`vrf_vxlan`
  description already calls this out as L3VNI-intended)
