# Ticket: Reconcile cluster-104 RouterOS BGP and remove temporary static routes

- Status: Resolved
- Priority: Medium
- Area: cluster-104 networking, RouterOS, Cilium BGP
- Created: 2026-07-03
- Updated: 2026-07-06

## Summary

`cluster-104` originally relied on manually-added RouterOS static routes for
the cluster pod and LoadBalancer ranges. Dynamic routing is now working live:
`talos01` runs BIRD, Cilium peers locally into BIRD, and RouterOS learns the
active cluster-104 pod and Home Assistant gateway VIP routes over BGP.

The original debt is resolved:

1. The live RouterOS BGP template and BGP connections are imported into the
   local RouterOS Terraform state.
2. The temporary broad static routes were removed after confirming BGP covers
   the active cluster-104 pod and LoadBalancer routes.

The broader RouterOS state issue remains tracked separately in the cluster-104
README: the RouterOS live stack still does not have full device state imported,
so a full `terragrunt apply` is not yet safe.

## Current State

The following broad routes were added manually during cutover and have now been
removed:

| Route | Next hop |
| --- | --- |
| `10.104.224.0/20` | `10.104.0.4` |
| `10.104.250.0/24` | `10.104.0.4` |
| `fd00:104:224::/60` | `fd00:104::4` |
| `fd00:104:250::/112` | `fd00:104::4` |

The live and state-managed BGP peer is:

| RouterOS connection | Local AS | Remote | Remote AS |
| --- | ---: | --- | ---: |
| `CLUSTER104_TALOS01` | `4200001000` | `fd00:104::4` | `4210104004` |

RouterOS currently learns these active BGP routes from cluster-104:

| Route | Source |
| --- | --- |
| `10.104.224.0/24` | Cilium pod CIDR via BIRD |
| `10.104.250.11/32` | `gateway-internal` VIP via BIRD |
| `10.104.250.12/32` | `gateway-tunnel` VIP via BIRD |
| `fd00:104:224::/64` | Cilium pod CIDR via BIRD |
| `fd00:104:250::11/128` | `gateway-internal` VIP via BIRD |
| `fd00:104:250::12/128` | `gateway-tunnel` VIP via BIRD |

Current Home Assistant gateway addresses on `cluster-104`:

| Gateway | IPv4 | IPv6 |
| --- | --- | --- |
| `gateway-internal` | `10.104.250.11` | `fd00:104:250::11` |
| `gateway-tunnel` | `10.104.250.12` | `fd00:104:250::12` |

ExternalDNS currently owns the `hass*.sulibot.com` records with TXT owner
`cluster-104`.

## Evidence

- Before adding routing coverage, traffic toward `10.104.250.12` fell through
  to the default/WAN path instead of staying on RouterOS. A traceroute went to
  `10.30.0.254` and then `192.168.1.254`.
- RouterOS had connected routes for the node VLAN only:
  `10.104.0.0/24` and `fd00:104::/64`.
- Cilium BGP on cluster-104 showed a local BIRD session established:
  local AS `4220104000` to peer AS `4210104004` on `::1:179`.
- After disabling BFD for the direct bare-metal upstream and adding the
  `CLUSTER104_TALOS01` peer, RouterOS shows an established session to
  `fd00:104::4` with remote router ID `10.104.254.4`, and active BGP routes
  for the current pod and gateway VIP prefixes.

## Impact

- Home Assistant cutover works now.
- The cluster-104 BGP connection is no longer live-only; it is imported into
  RouterOS Terraform state.
- Temporary broad static routes no longer mask BGP behavior.
- The broader RouterOS live stack still needs full state reconciliation before
  a full-device apply is safe.

## Acceptance Criteria

- [x] RouterOS Terraform state includes `CLUSTER104_TALOS01`.
- [x] A targeted RouterOS BGP plan does not try to recreate the live cluster-104
  BGP connection.
- [x] No unmanaged manual static routes are required for:
  - `10.104.224.0/20`
  - `10.104.250.0/24`
  - `fd00:104:224::/60`
  - `fd00:104:250::/112`
- [x] `10.104.250.11`, `10.104.250.12`, `fd00:104:250::11`, and
  `fd00:104:250::12` are reachable from the management network without falling
  back to a default/WAN route.
- [x] `hass*.sulibot.com` continues to resolve to cluster-104 addresses, and the
  old cluster continues to skip those records because the TXT owner is
  `cluster-104`.
- [x] `terraform/infra/live/baremetal/cluster-104/README.md` documents the final
  routing posture.

## Related Files

- `kubernetes/clusters/cluster-104/cilium-bgp/bgp.yaml`
- `kubernetes/clusters/cluster-104/network/`
- `kubernetes/clusters/cluster-104/external-dns/helmrelease.yaml`
- `terraform/infra/live/baremetal/cluster-104/README.md`
- `terraform/infra/live/routeros/terragrunt.hcl`
- `terraform/infra/modules/routeros/`
