resource "routeros_routing_filter_rule" "rules" {
  for_each = { for i, r in var.routing_filter_rules : tostring(i) => r }

  chain    = each.value.chain
  rule     = each.value.rule
  comment  = each.value.comment != "" ? each.value.comment : null
  disabled = each.value.disabled
}

# routeros_routing_bfd_configuration is not available in provider v1.86.3 — Phase 3.
