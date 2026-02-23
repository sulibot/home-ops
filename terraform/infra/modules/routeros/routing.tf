resource "routeros_routing_filter_rule" "rules" {
  for_each = { for i, r in var.routing_filter_rules : tostring(i) => r }

  chain    = each.value.chain
  rule     = each.value.rule
  comment  = each.value.comment != "" ? each.value.comment : null
  disabled = each.value.disabled
}

# routeros_routing_bfd_configuration: provider v1.99.0 validates addresses as
# plain IPs but RouterOS BFD uses CIDR notation — provider bug, skip for now.
