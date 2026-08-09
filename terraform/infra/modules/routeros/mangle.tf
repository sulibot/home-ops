resource "routeros_ip_firewall_mangle" "rules" {
  for_each = { for i, r in var.firewall_mangle_rules : tostring(i) => r }

  chain          = each.value.chain
  action         = each.value.action
  comment        = each.value.comment != "" ? each.value.comment : null
  disabled       = each.value.disabled
  protocol       = each.value.protocol
  tcp_flags      = each.value.tcp_flags
  in_interface   = each.value.in_interface
  out_interface  = each.value.out_interface
  new_mss        = each.value.new_mss
  passthrough    = each.value.passthrough
}
