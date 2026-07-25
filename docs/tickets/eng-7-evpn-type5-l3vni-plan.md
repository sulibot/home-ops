# Plan: wire up EVPN Type-5/symmetric-IRB via the existing L3VNI

Written 2026-07-14, planning-only (no live changes made). Follow-up to
ENG-7/ENG-10 - the four workarounds tried there all hit the same
architectural wall (VRF-leaked/point-to-point routes can't resolve
link-local next-hops across nodes). This is the actual fix.

Renamed 2026-07-24 from `eng11-evpn-type5-l3vni-plan.md`: this is a design
doc referenced from ENG-7, not its own tracked Linear issue - the old
filename collided with the real ENG-11 (OTEL pipeline migration, unrelated
topic). Still on hold per ENG-7; not implemented.

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

## Update 2026-07-25: scope confirmed broader, root cause pinpointed, ready to execute

During a Plex outage investigation, hit the same failure signature this
plan describes, but on different prefixes than the original VIP. Confirmed
live on `pve01`:

- Zebra logs `[X5XE1-RS0SW][EC 4043309074] Failed to install Nexthop
  (N[addr if 14 vrfid 0]) into the kernel` and `Nexthop id does not exist`
  for routes leaked via `import vrf` between `vrf_evpnz1` and the global
  table - interface index 14 is `vrf_evpnz1` itself, incorrectly used as
  an egress device for a recursively-resolved next-hop.
- This affects **Ceph mon/OSD reachability** (`fc00:20::1/2/3`, the
  storage public network on the PVE hosts) - not just the apiserver VIP.
  This is what actually blocked Plex.
- It also affects **same-subnet cross-node VM traffic** (e.g. `solcp02`
  on `pve02` unreachable from `pve01`'s `vrf_evpnz1`), because even
  intra-`vnet101` reachability in this design goes through the same
  `VMS` dynamic-BGP-peer -> redistribute -> leak round trip, not pure
  L2 flood-and-learn. So the "Type-2 stays untouched" framing from the
  original plan was too narrow - Type-2 handles MAC/IP mobility during
  live migration fine and is unaffected, but same-subnet cross-node
  *reachability* in the current design rides the same broken leak path
  this plan already targets.
- **Confirmed reproducible, not stale/corrupted state**: identical error
  recurred immediately after 3 separate full host reboots (`pve02`,
  `pve03`, `pve01`) and after an FRR 10.6.1 -> 10.7.0 package upgrade on
  `pve01`. Ruled out: kernel nexthop-table corruption from a one-time
  event, FRR version bug fixed upstream, BGP soft-clear recovery. This is
  a live, deterministic bug in the leak/recursive-nexthop path, not
  something that self-heals or that a restart clears.

### Ownership boundary, confirmed

- **Terraform is already correct, no changes needed there.**
  `terraform/infra/live/common/0-sdn-setup/terragrunt.hcl` sets
  `vrf_vxlan = 4096` and `rt_import = "65000:1"`, which is exactly what
  drives PVE's own native SDN-to-FRR generator to produce `vrf
  vrf_evpnz1 / vni 4096` and a `default-originate ipv4/ipv6` +
  `route-target import 65000:1` block under the VRF's BGP instance
  (verified against `/etc/frr/frr.conf.sdn-generated-20260712` on
  `pve01` - a snapshot of PVE's native, pre-ansible-overlay output).
- **The gap is entirely in Ansible.**
  `ansible/pve/roles/frr/templates/frr-pve.conf.j2` fully replaces FRR's
  config (needed for the custom `VMS` dynamic peer-group,
  `RM_GLOBAL_TO_VRF_V6`/`RM_VRF_TO_GLOBAL_V6`, OSPF underlay, etc. - none
  of which PVE's SDN system knows how to generate), and in doing so has
  silently dropped the `vni` interface binding that PVE would otherwise
  generate. Confirmed absent in both the current live config and a
  `frr.conf.pre-type5-fix-20260713-161725` backup, so this has been
  missing since at least 2026-07-13.
- `default-originate` (PVE's native use of the same L3VNI, scoped to
  default-route/exit-node behavior via `exitnodes-local-routing 1`,
  already live and working) is a different, narrower use of Type-5 than
  what's needed here (`advertise ipv4/ipv6 unicast`, specific-prefix
  advertisement) - keep `default-originate` as-is, it's unrelated and
  not in conflict.

### Config change (refined from the original proposal above)

Per PVE node, in `frr-pve.conf.j2`:

```
vrf {{ VRF_NAME }}
 vni {{ vrf_vxlan_id }}
exit-vrf
!
router bgp {{ LOCAL_AS }} vrf {{ VRF_NAME }}
 ...
 address-family l2vpn evpn
  vni {{ vrf_vxlan_id }}
  advertise ipv4 unicast
  advertise ipv6 unicast
 exit-address-family
exit
```

`vrf_vxlan_id` from `network_facts.sdn_vrf_vxlan` (same source as noted
in the original plan above, no new plumbing).

### Validation sequence (execute in this order, don't batch)

1. Render template, syntax-check only (`vtysh -f <file> -C`), no live
   apply.
2. Apply live on `pve01` only via interactive `vtysh -c 'configure
   terminal'` (not `ifreload`/ansible push) - trivially reversible with
   `no vni {{ id }}` / removing the `advertise` lines.
3. Confirm `show bgp l2vpn evpn vni` on `pve01` shows `Number of L3
   VNIs: 1` (baseline today: 0).
4. Advertise a throwaway test prefix, confirm `Status: Installed` (not
   `Status: Failed`) on `pve02` and `pve03` - the actual proof the
   recursive-nexthop bug is bypassed.
5. Verify against a real currently-broken address (`fc00:20::2` from a
   pod on `solwk01`) before declaring success.
6. Only then commit to the ansible template and roll to all 3 nodes.

**Explicitly ruled out as remediation, don't retry**: host reboots, FRR
daemon restart, BGP soft-clear, FRR package upgrade - all tried live on
2026-07-25, none fixed it. Get explicit sign-off before any action
beyond the single-node `pve01` live trial in step 2 - this touches
production Ceph/Kubernetes storage networking.

### Current blocker this unblocks

Plex (`default` namespace, cluster-101) is scaled to 0 replicas, waiting
on this fix. Its `Preferences.xml` is also empty (0 bytes) - a separate,
already-diagnosed follow-up (clear the file, let Plex regenerate it) -
do not restart Plex until `fc00:20::2`/`fc00:20::3` reachability from a
pod on `solwk01` is confirmed working first.

## Follow-up: ENG-320/ENG-321 (2026-07-25)

Two follow-on tickets came out of this incident, both now closed:

**ENG-320 (Done)** - the ansible FRR role was found to hand-author a full
replacement `frr.conf`, including sections (e.g. the `vrf vrf_evpnz1 /
vni 4096` binding) PVE's own SDN generator already produces natively.
Landed via PVE SDN Fabrics (`proxmox_sdn_fabric_ospf` +
`proxmox_sdn_fabric_node_ospf`, Terraform-native as of `bpg/proxmox`
0.111.1 / PVE 9.2) migrating the OSPF underlay for the two mesh links
off hand-rolled FRR config. Rolled out node-by-node with full
verification; see `terraform/infra/modules/proxmox_sdn/main.tf` and
`terraform/infra/live/common/0-sdn-setup/terragrunt.hcl`.

This surfaced a real bug: the ansible role wrote the same template
directly to both `/etc/frr/frr.conf` and `/etc/frr/frr.conf.local`.
Since PVE merges `frr.conf.local` into its own generated `frr.conf` on
SDN apply, the direct write was silently clobbering Fabric-generated
content on every ansible run. Fixed: the role now only writes
`frr.conf.local` and triggers `pvesh set /cluster/sdn` to regenerate
`frr.conf` correctly. Commit `106ae183`.

**ENG-321 (Canceled)** - explored replacing the `VMS` dynamic BGP
peer-group (which tenant K8s VMs use to advertise pod CIDRs/node
loopbacks into each hypervisor's VRF) with static Terraform-declared
`proxmox_sdn_subnet` resources. Refuted at the research stage: that
resource's `gateway` is a single string scoped to the zone-wide anycast
gateway, with no per-VM/per-node gateway concept - the entire premise
didn't hold. Forum/docs research afterward found no better native or
community-standard alternative (bypassing the fabric costs VM
live-migration mobility; Cilium tunnel mode means double VXLAN
encapsulation for no complexity win; PVE SDN Fabrics only manages
underlay, not tenant-route redistribution). The `VMS` peer-group and its
route-maps remain the intentional, documented mechanism for this
traffic class going forward.
