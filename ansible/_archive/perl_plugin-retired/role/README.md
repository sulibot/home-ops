# perl_plugin

Deploys custom Perl modules that **overwrite PVE's own stock SDN BGP
controller** at `/usr/share/perl5/PVE/Network/SDN/Controllers/`:

- `templates/plugin.pm.j2` -> `Plugin.pm`
- `templates/BgpPlugin.j2` -> `BgpPlugin.pm`

This is a different, more invasive class of customization than the
`frr`/`interfaces` role templates: it patches how Proxmox's own SDN
subsystem generates BGP config in the first place, which is directly
relevant to the "PVE SDN regenerates frr.conf at boot" root cause
documented in `docs/tickets/pve-frr-power-event-20260712.md`.

The tasks already back up the original stock file to `*.pm.orig` on first
run (only if no backup exists yet), so the pre-patch version is recoverable
on any node that's already had this role applied.

## Diff against current stock (done 2026-07-14, via git.proxmox.com/pve-network)

**Not just a version-pinned copy - this targets an older pve-network
internal API and is NOT safe to apply blindly to a freshly-built PVE 9.x
node:**

- Current stock `BgpPlugin.pm`/`Plugin.pm` build a **structured** config
  tree: `$config->{frr}->{bgp}->{vrf_router}->{'default'}` with
  `neighbor_groups`/`address_families` arrays, and support BGP Fabrics +
  EVPN auto-ASN arbitration via `get_default_router_asn()` (a whole
  function our version doesn't have at all).
- Our `plugin.pm.j2`/`BgpPlugin.j2` instead push **raw config-line
  strings** onto `$config->{frr}->{router}->{"bgp $asn"}` and
  `$config->{frr_prefix_list}` / `$config->{frr_routemap}` - an older,
  structurally different schema.
- If PVE's own FRR-config renderer (elsewhere in `pve-network`, not in
  these two files) has been updated to only understand the new structured
  format, installing our old-format plugin would likely **break PVE's
  SDN->FRR generation entirely** on a fresh PVE 9.x (trixie) install - not
  a cosmetic difference.
- Our `get_router_id()` is also independently hardened vs. stock (4-step
  fallback: explicit IP -> IP on named iface -> any host IPv4 -> MAC-derived,
  with clear die messages) vs. stock's simpler explicit-IP-or-MAC-only
  logic. That part looks like a deliberate, reasonable improvement -
  it's the FRR-config data-model mismatch above that's the real risk.
- Stock's base `Plugin.pm` also declares `route-map-in`/`route-map-out` in
  its shared `propertyList`; ours doesn't expose those at all, so any SDN
  BGP controller config relying on route-maps-via-UI wouldn't be
  configurable through this patched version.

**Before relying on this for a from-scratch PVE 9.x build:** confirm what's
actually loaded on a live node (`diff *.pm.orig *.pm` if the role's already
run there, or `cat` the live files if not) - this repo's sandbox has no
network route to the live PVE nodes, so that live-side comparison hasn't
been done, only the stock-vs-template diff above. It's possible the live
nodes are still running against an intermediate pve-network version where
this works fine; don't assume either way without checking. Not included in
`playbooks/site.yml`'s default sequence pending that check - see
`ansible/pve/README.md`.
