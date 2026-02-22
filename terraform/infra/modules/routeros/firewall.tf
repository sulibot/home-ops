# Firewall filter rules, NAT rules, and address-list entries.
#
# Ordering note: RouterOS evaluates filter rules by their position on-device.
# The for_each key is the list index (tostring(i)), so Terraform tracks each rule
# by its position in the input list. Re-ordering the list = destroy + recreate.
# Use the `place_before` attribute for surgical insertion if needed.

resource "routeros_ip_firewall_filter" "rules" {
  for_each = { for i, r in var.firewall_filter_rules : tostring(i) => r }

  chain    = each.value.chain
  action   = each.value.action
  comment  = each.value.comment != "" ? each.value.comment : null
  disabled = each.value.disabled

  protocol             = each.value.protocol
  connection_state     = each.value.connection_state
  in_interface_list    = each.value.in_interface_list
  out_interface_list   = each.value.out_interface_list
  src_address_list     = each.value.src_address_list
  dst_address_list     = each.value.dst_address_list
  connection_nat_state = each.value.connection_nat_state
  hw_offload           = each.value.hw_offload
  ipsec_policy         = each.value.ipsec_policy
}

resource "routeros_ip_firewall_nat" "rules" {
  for_each = { for i, r in var.firewall_nat_rules : tostring(i) => r }

  chain    = each.value.chain
  action   = each.value.action
  comment  = each.value.comment != "" ? each.value.comment : null
  disabled = each.value.disabled

  out_interface_list = each.value.out_interface_list
}

resource "routeros_ip_firewall_addr_list" "entries" {
  for_each = { for e in var.address_lists : "${e.list}-${e.address}" => e }

  list    = each.value.list
  address = each.value.address
  comment = each.value.comment != "" ? each.value.comment : null
}
