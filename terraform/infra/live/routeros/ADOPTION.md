# RouterOS Terraform Adoption

This stack is adopted for the currently managed RouterOS surface. As of the
2026-07-10 final adoption checkpoint, `terragrunt plan` for this stack is a
no-op: zero creates, zero updates, zero deletes.

Firewall filters, RouterOS management services, and global DNS settings are
intentionally unmanaged for now. Do not add them back to desired config until
their live/provider issues below are resolved.

As of 2026-07-07, the stack had zero Terraform state entries and the plan wanted
to create 207 resources. That was an adoption gap, not a safe apply plan.

As of 2026-07-08, the first read-only import batches are complete. Do not run
`terragrunt apply` yet: the remaining plan still contains 129 creates and some
resource groups need import or modeling decisions before adoption.

As of 2026-07-10, additional read-only imports brought state to 164 resources.
VLAN 104 was already partially modeled, but its IPv6 neighbor discovery and
NAT66 ULA address-list rows were missing from desired config; both are now
modeled and imported from live RouterOS rows. Static DNS records, bridge VLAN
rows, IPv4 firewall address lists, the desired NAT singleton, and DHCP leases
that matched live were also imported.

The final 2026-07-10 adoption pass then made unmanaged/problem areas explicit:
IPv4/IPv6 firewall filter rules are excluded until cleanup, `ip_service`
resources are excluded because provider import fails, and `ip_dns` global
settings are excluded because the singleton is not importable. The disabled
legacy `pve04` AAAA record was removed from desired state because it does not
exist live.

Planned create count by resource type:

| Count | Resource type |
| ---: | --- |
| 27 | `routeros_ipv6_firewall_filter` |
| 25 | `routeros_ip_dns_record` |
| 16 | `routeros_ip_firewall_filter` |
| 14 | `routeros_interface_list_member` |
| 8 | `routeros_ipv6_dhcp_client` |
| 8 | `routeros_ip_service` |
| 8 | `routeros_ip_address` |
| 7 | `routeros_ipv6_address` |
| 7 | `routeros_bridge_port` |
| 6 | `routeros_routing_ospf_interface_template` |
| 6 | `routeros_routing_filter_rule` |
| 6 | `routeros_ipv6_firewall_addr_list` |
| 6 | `routeros_ip_pool` |
| 6 | `routeros_ip_dhcp_server_option` |
| 6 | `routeros_interface_vlan` |
| 6 | `routeros_bridge_vlan` |
| 5 | `routeros_ip_dhcp_server_option_set` |
| 4 | `routeros_ipv6_neighbor_discovery` |
| 4 | `routeros_ip_firewall_addr_list` |
| 4 | `routeros_ip_dhcp_server_network` |
| 4 | `routeros_ip_dhcp_server_lease` |
| 4 | `routeros_ip_dhcp_server` |
| 2 | `routeros_routing_ospf_instance` |
| 2 | `routeros_routing_ospf_area` |
| 2 | `routeros_interface_list` |
| 2 | `routeros_bridge` |
| 1 each | DNS settings, system identity/clock/NTP, IP/IPv6 settings, SNMP, BGP template/connection, NAT |

Current import progress:

| Count | Imported resource type |
| ---: | --- |
| 15 | `routeros_interface_list_member` |
| 24 | `routeros_ip_dns_record` |
| 9 | `routeros_ip_address` |
| 8 | `routeros_ipv6_address` |
| 7 | `routeros_bridge_vlan` |
| 7 | system/IP/IPv6/SNMP singleton resources |
| 7 | `routeros_ip_pool` |
| 7 | `routeros_interface_vlan` |
| 7 | `routeros_bridge_port` |
| 7 | `routeros_ipv6_firewall_addr_list` |
| 6 | `routeros_ip_dhcp_server_option` |
| 6 | `routeros_routing_ospf_interface_template` |
| 6 | `routeros_routing_filter_rule` |
| 5 | `routeros_ipv6_neighbor_discovery` |
| 5 | `routeros_ip_dhcp_server_option_set` |
| 5 | `routeros_ip_dhcp_server_network` |
| 5 | `routeros_ip_dhcp_server` |
| 4 | `routeros_ip_dhcp_server_lease` |
| 4 | `routeros_ip_firewall_addr_list` |
| 2 | `routeros_routing_ospf_instance` |
| 2 | `routeros_routing_ospf_area` |
| 1 | `routeros_routing_bgp_template` |
| 1 | `routeros_routing_bgp_connection` |
| 1 | `routeros_ip_firewall_nat` |
| 2 | `routeros_bridge` |
| 2 | `routeros_interface_list` |
| 1 | `routeros_snmp_community` |

Current remaining plan count by resource type, from
`/tmp/routeros-final-adoption.plan`:

| Count | Resource type |
| ---: | --- |
| 0 | none |

The remaining plan has no in-place updates:

| Resource | Change |
| --- | --- |
| none | none |

Recommended adoption order:

1. Read-only system objects: identity, clock, NTP, IP/IPv6 settings, DNS
   settings, SNMP.
2. Passive naming/inventory: interface lists, static DNS records.
3. L2 and addressing: bridges, bridge ports/VLANs, VLAN interfaces, IP/IPv6
   addresses.
4. DHCP pools/options/servers/leases.
5. Routing objects: BGP, OSPF, routing filter rules.
6. Firewall address lists and filter/NAT rules, only after exporting current
   rule order and confirming the Terraform list order matches RouterOS exactly.

Operational notes:

- RouterOS firewall rule order matters. Importing or applying with a mismatched
  list index can reorder policy.
- Static DNS has duplicate disabled legacy A records on the router. Resolve
  duplicates before importing DNS records into a `type-name` keyed Terraform map.
- All desired static DNS records that existed live were imported. The disabled
  legacy `AAAA-pve04.sulibot.com` desired record was removed because it does
  not currently exist live.
- The provider reports `routeros_ip_dns` does not support import. Treat DNS
  global settings as a reviewed apply-only adoption step.
- `routeros_ip_service` resources are unmanaged. Imports did not stick by
  service name or internal ID,
  even though the provider found candidate IDs. Re-tested on 2026-07-10 with
  live internal IDs such as `*1` for `ftp`; the provider still reported
  non-existent remote objects. Leave management services unmanaged until this
  provider/import behavior is resolved.
- Source L2 inventory was reconciled on 2026-07-08 to match live
  `talos01[ether5]`, `jetkvm-talos01[ether7]`, and VLAN 104.
- VLAN 104 now includes IPv6 neighbor discovery and NAT66 ULA modeling:
  `routeros_ipv6_neighbor_discovery.interfaces["vlan104"]` imported from `*33`,
  and `routeros_ipv6_firewall_addr_list.entries["NAT66-ULA-fd00:104::/48"]`
  imported from `*7`.
- Bridge VLAN membership is adopted. VLAN 1 follows RouterOS live behavior:
  `pve03[ether4]` is represented by the dynamic PVID row instead of the static
  VLAN 1 row.
- DHCP pools, options, option sets, servers, networks, and desired leases are
  adopted. The Omada AP lease at `10.30.0.1` replaced the stale desired
  SynologyRouter MAC; the old live SynologyRouter lease at `10.30.0.2` remains
  unmanaged.
- Live has a duplicate IPv4 masquerade NAT rule; Terraform manages the desired
  first row only and leaves the duplicate unmanaged for explicit cleanup later.
- IPv4 and IPv6 firewall filter rules are unmanaged. Live tables contain
  duplicated historical rules and do not match the old Terraform rule order.
  Do not add firewall rules back until deciding whether to codify the live
  table first or clean it up manually.
- BGP `add_path_out` is ignored in lifecycle because RouterOS reads it as unset
  while the provider wants to materialize the effective default `none`.
- The Proxmox host `AAAA` records were manually corrected on 2026-07-07 to point
  at infra loopbacks `fd00:0:0:ffff::1/2/3`; the Terraform desired config now
  matches that.
- Use `terragrunt plan -out=/tmp/routeros-adoption.plan` and
  `terragrunt show -json /tmp/routeros-adoption.plan` to audit progress after
  each import batch.
