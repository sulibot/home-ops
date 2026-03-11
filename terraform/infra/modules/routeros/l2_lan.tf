resource "routeros_bridge" "bridges" {
  for_each = { for b in var.bridges : b.name => b }

  name           = each.value.name
  comment        = each.value.comment != "" ? each.value.comment : null
  admin_mac      = each.value.admin_mac
  auto_mac       = each.value.auto_mac
  igmp_snooping  = each.value.igmp_snooping
  pvid           = each.value.pvid
  protocol_mode  = each.value.protocol_mode
  vlan_filtering = each.value.vlan_filtering
  disabled       = each.value.disabled
}

resource "routeros_bridge_port" "ports" {
  for_each = { for p in var.bridge_ports : p.interface => p }

  bridge    = each.value.bridge
  interface = each.value.interface
  comment   = each.value.comment != "" ? each.value.comment : null
  disabled  = each.value.disabled
  pvid      = each.value.pvid
}

resource "routeros_bridge_vlan" "vlans" {
  for_each = { for v in var.bridge_vlans : join(",", sort(tolist(v.vlan_ids))) => v }

  bridge    = each.value.bridge
  comment   = each.value.comment != "" ? each.value.comment : null
  disabled  = each.value.disabled
  tagged    = each.value.tagged
  untagged  = each.value.untagged
  vlan_ids  = each.value.vlan_ids
}

resource "routeros_interface_vlan" "interfaces" {
  for_each = { for v in var.vlan_interfaces : v.name => v }

  name     = each.value.name
  comment  = each.value.comment != "" ? each.value.comment : null
  disabled = each.value.disabled
  interface = each.value.interface
  vlan_id  = each.value.vlan_id
}

resource "routeros_ip_address" "addresses" {
  for_each = { for a in var.ipv4_addresses : "${a.interface}-${a.address}" => a }

  address   = each.value.address
  comment   = each.value.comment != "" ? each.value.comment : null
  disabled  = each.value.disabled
  interface = each.value.interface
  network   = each.value.network
}

resource "routeros_ipv6_dhcp_client" "clients" {
  for_each = { for c in var.ipv6_dhcp_clients : c.interface => c }

  interface                     = each.value.interface
  comment                       = each.value.comment != "" ? each.value.comment : null
  disabled                      = each.value.disabled
  request                       = each.value.request
  accept_prefix_without_address = each.value.accept_prefix_without_address
  add_default_route             = each.value.add_default_route
  allow_reconfigure             = each.value.allow_reconfigure
  check_gateway                 = each.value.check_gateway
  default_route_tables          = each.value.default_route_tables
  pool_name                     = each.value.pool_name
  pool_prefix_length            = each.value.pool_prefix_length
  prefix_address_lists          = each.value.prefix_address_lists
  script                        = each.value.script
  use_peer_dns                  = each.value.use_peer_dns
  validate_server_duid          = each.value.validate_server_duid
}
