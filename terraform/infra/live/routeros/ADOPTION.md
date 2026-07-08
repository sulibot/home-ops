# RouterOS Terraform Adoption

This stack is not adopted yet. Do not run `terragrunt apply` here until the
existing RouterOS configuration has been imported or the plan has been reduced
to a reviewed, intentional change set.

As of 2026-07-07, the stack had zero Terraform state entries and the plan wanted
to create 207 resources. That was an adoption gap, not a safe apply plan.

As of 2026-07-08, the first read-only import batches are complete. Do not run
`terragrunt apply` yet: the remaining plan still contains 129 creates and some
resource groups need import or modeling decisions before adoption.

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
| 9 | `routeros_ip_address` |
| 8 | `routeros_ipv6_address` |
| 7 | system/IP/IPv6/SNMP singleton resources |
| 7 | `routeros_ip_pool` |
| 7 | `routeros_interface_vlan` |
| 7 | `routeros_bridge_port` |
| 6 | `routeros_ip_dhcp_server_option` |
| 5 | `routeros_ip_dhcp_server_option_set` |
| 5 | `routeros_ip_dhcp_server_network` |
| 5 | `routeros_ip_dhcp_server` |
| 2 | `routeros_bridge` |
| 2 | `routeros_interface_list` |
| 1 | `routeros_snmp_community` |

Current remaining create count by resource type:

| Count | Resource type |
| ---: | --- |
| 27 | `routeros_ipv6_firewall_filter` |
| 25 | `routeros_ip_dns_record` |
| 16 | `routeros_ip_firewall_filter` |
| 8 | `routeros_ipv6_dhcp_client` |
| 8 | `routeros_ip_service` |
| 7 | `routeros_bridge_vlan` |
| 6 | `routeros_routing_ospf_interface_template` |
| 6 | `routeros_routing_filter_rule` |
| 6 | `routeros_ipv6_firewall_addr_list` |
| 4 | `routeros_ipv6_neighbor_discovery` |
| 4 | `routeros_ip_firewall_addr_list` |
| 4 | `routeros_ip_dhcp_server_lease` |
| 2 | `routeros_routing_ospf_instance` |
| 2 | `routeros_routing_ospf_area` |
| 1 each | DNS settings, BGP template/connection, NAT |

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
- The provider reports `routeros_ip_dns` does not support import. Treat DNS
  global settings as a reviewed apply-only adoption step.
- `routeros_ip_service` imports did not stick by service name or internal ID,
  even though the provider found candidate IDs. Leave management services out of
  apply plans until this provider/import behavior is resolved.
- Source L2 inventory was reconciled on 2026-07-08 to match live
  `talos01[ether5]`, `jetkvm-talos01[ether7]`, and VLAN 104.
- Bridge VLAN membership still needs care. Live VLAN 1 exists as two RouterOS
  rows, while the current module keys bridge VLANs by VLAN ID. Decide whether to
  normalize live VLAN 1 into one row or change the module key before importing
  bridge VLAN membership.
- DHCP pools, options, option sets, servers, and networks are adopted. DHCP
  leases are not adopted yet: live has moved/changed some static assignments
  compared with Terraform, and the Talos PXE lease differs from the generated
  desired lease.
- The Proxmox host `AAAA` records were manually corrected on 2026-07-07 to point
  at infra loopbacks `fd00:0:0:ffff::1/2/3`; the Terraform desired config now
  matches that.
- Use `terragrunt plan -out=/tmp/routeros-adoption.plan` and
  `terragrunt show -json /tmp/routeros-adoption.plan` to audit progress after
  each import batch.
