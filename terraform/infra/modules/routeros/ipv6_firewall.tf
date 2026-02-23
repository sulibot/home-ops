# IPv6 firewall address-list entries and filter rules.
# Ordering follows the same pattern as IPv4: list index = position on device.

resource "routeros_ipv6_firewall_addr_list" "entries" {
  for_each = { for e in var.ipv6_address_lists : "${e.list}-${e.address}" => e }

  list    = each.value.list
  address = each.value.address
  comment = each.value.comment != "" ? each.value.comment : null
}

resource "routeros_ipv6_firewall_filter" "rules" {
  for_each = { for i, r in var.ipv6_firewall_filter_rules : tostring(i) => r }

  chain    = each.value.chain
  action   = each.value.action
  comment  = each.value.comment != "" ? each.value.comment : null
  disabled = each.value.disabled

  protocol           = each.value.protocol
  connection_state   = each.value.connection_state
  in_interface_list  = each.value.in_interface_list
  out_interface_list = each.value.out_interface_list
  src_address_list   = each.value.src_address_list
  dst_address_list   = each.value.dst_address_list
  src_address        = each.value.src_address
  dst_address        = each.value.dst_address
  dst_port           = each.value.dst_port
  hop_limit          = each.value.hop_limit
  ipsec_policy       = each.value.ipsec_policy
  log_prefix         = each.value.log_prefix
}
