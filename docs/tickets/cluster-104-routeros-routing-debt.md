# Ticket: Replace cluster-104 temporary RouterOS static routes

- Status: Open
- Priority: Medium
- Area: cluster-104 networking, RouterOS, Cilium BGP
- Created: 2026-07-03

## Summary

`cluster-104` is currently reachable because RouterOS has manually-added static
routes for the cluster pod and LoadBalancer ranges. This is acceptable as a
temporary cutover measure for Home Assistant, but it leaves the routing model
split between Git-managed intent and live router state.

The intended long-term shape is one of:

1. Prefer dynamic routing: fix BGP export from `talos01`/BIRD/Cilium to
   RouterOS so RouterOS learns the cluster-104 pod and LoadBalancer routes.
2. If cluster-104 is intentionally static because it is a single bare-metal
   node, codify the static routes in RouterOS Terraform after the RouterOS
   state is reconciled/imported.

## Current Workaround

The following routes were added manually on RouterOS:

| Route | Next hop |
| --- | --- |
| `10.104.224.0/20` | `10.104.0.4` |
| `10.104.250.0/24` | `10.104.0.4` |
| `fd00:104:224::/60` | `fd00:104::4` |
| `fd00:104:250::/112` | `fd00:104::4` |

Current Home Assistant gateway addresses on `cluster-104`:

| Gateway | IPv4 | IPv6 |
| --- | --- | --- |
| `gateway-internal` | `10.104.250.11` | `fd00:104:250::11` |
| `gateway-tunnel` | `10.104.250.12` | `fd00:104:250::12` |

ExternalDNS currently owns the `hass*.sulibot.com` records with TXT owner
`cluster-104`.

## Evidence

- Before adding the static routes, traffic toward `10.104.250.12` fell through
  to the default/WAN path instead of staying on RouterOS. A traceroute went to
  `10.30.0.254` and then `192.168.1.254`.
- RouterOS had connected routes for the node VLAN only:
  `10.104.0.0/24` and `fd00:104::/64`.
- Cilium BGP on cluster-104 showed a local BIRD session established:
  local AS `4220104000` to peer AS `4210104004` on `::1:179`.
- RouterOS did not have the `10.104.250.0/24` LoadBalancer route until it was
  added manually.

## Impact

- Home Assistant cutover works now.
- A router rebuild or a full RouterOS Terraform apply could remove or duplicate
  the manually-added routes.
- The repo does not yet fully express the live routing requirement for
  cluster-104 pod and LoadBalancer reachability.
- The cluster-104 networking pattern is not yet aligned with the intended
  Git-managed routing control plane.

## Acceptance Criteria

- RouterOS learns or owns these routes through a managed source:
  - BGP dynamic routes from cluster-104, or
  - Terraform-managed static routes with reconciled/imported RouterOS state.
- No unmanaged manual static routes are required for:
  - `10.104.224.0/20`
  - `10.104.250.0/24`
  - `fd00:104:224::/60`
  - `fd00:104:250::/112`
- `10.104.250.11`, `10.104.250.12`, `fd00:104:250::11`, and
  `fd00:104:250::12` are reachable from the management network without falling
  back to a default/WAN route.
- `hass*.sulibot.com` continues to resolve to cluster-104 addresses, and the
  old cluster continues to skip those records because the TXT owner is
  `cluster-104`.
- `terraform/infra/live/baremetal/cluster-104/README.md` documents the final
  routing posture.

## Related Files

- `kubernetes/clusters/cluster-104/cilium-bgp/bgp.yaml`
- `kubernetes/clusters/cluster-104/network/`
- `kubernetes/clusters/cluster-104/external-dns/helmrelease.yaml`
- `terraform/infra/live/baremetal/cluster-104/README.md`
- `terraform/infra/live/routeros/terragrunt.hcl`
- `terraform/infra/modules/routeros/`
