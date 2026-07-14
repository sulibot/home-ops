# Archived: perl_plugin (retired by preference, not Terraform-redundant)

Archived 2026-07-14, decided during the lae.proxmox refactor
(`.claude/plans/declarative-forging-volcano.md`).

Unlike the roles in `ansible/_archive/terraform-managed-redundant/`, this
one isn't redundant with anything - Terraform doesn't manage PVE's SDN BGP
controller Perl internals. It's retired by explicit preference: this role
overwrote Proxmox's own stock
`/usr/share/perl5/PVE/Network/SDN/Controllers/{Plugin,BgpPlugin}.pm` with a
custom-patched version, and patched vendor files are hard to keep track of
and silently break on upgrade.

## What the diff found (2026-07-14, stock-vs-template only)

Diffed against current stock `PVE::Network::SDN::Controllers::*` from
`git.proxmox.com/pve-network`: this patch targets an **older** pve-network
internal data model (raw config-string pushes onto
`$config->{frr}->{router}->{"bgp $asn"}`) vs. current stock's structured
`vrf_router`/BGP-Fabrics model with EVPN auto-ASN arbitration
(`get_default_router_asn()`, absent from this patch entirely). It was
already at real risk of breaking PVE's own SDN->FRR generation on a
freshly-built PVE 9.x node - full writeup was in this role's README before
archival, reproduced below.

## Before deleting this permanently

Nobody currently knows *why* this patch was originally written - what
problem in stock Proxmox's BGP controller it was solving. Before deleting
outright:

1. Check whether it's still active on any live node:
   `ls /usr/share/perl5/PVE/Network/SDN/Controllers/*.orig` on pve01-03 -
   if a `.orig` backup exists, this patch is currently deployed there and
   something may depend on its behavior.
2. If it is active, diff `*.orig` against the live `.pm` to see exactly
   what changed, and confirm current stock PVE (verified diff above)
   already covers whatever that was for before removing the patch from a
   live node.
3. If it's not active anywhere, this is safe to delete outright rather
   than keep archived.

---

Original role README, preserved for context:

# perl_plugin

Deploys custom Perl modules that overwrote PVE's own stock SDN BGP
controller at `/usr/share/perl5/PVE/Network/SDN/Controllers/`:

- `templates/plugin.pm.j2` -> `Plugin.pm`
- `templates/BgpPlugin.j2` -> `BgpPlugin.pm`

The tasks backed up the original stock file to `*.pm.orig` on first run
(only if no backup existed yet), so the pre-patch version is recoverable on
any node that already had this role applied.

Our `get_router_id()` was independently hardened vs. stock (4-step
fallback: explicit IP -> IP on named iface -> any host IPv4 -> MAC-derived,
with clear die messages) vs. stock's simpler explicit-IP-or-MAC-only logic
- that part looked like a deliberate, reasonable improvement. It's the
FRR-config data-model mismatch that made this unsafe to keep using
unpatched-vs-stock long-term, independent of the "hard to keep track of"
preference that ultimately decided this.
