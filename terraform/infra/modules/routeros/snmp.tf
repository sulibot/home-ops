resource "routeros_snmp" "this" {
  count = var.snmp != null ? 1 : 0

  enabled          = var.snmp.enabled
  contact          = var.snmp.contact
  location         = var.snmp.location
  src_address      = var.snmp.src_address
  trap_interfaces  = var.snmp.trap_interfaces
  trap_target      = var.snmp.trap_target
  vrf              = var.snmp.vrf
  engine_id_suffix = var.snmp.engine_id_suffix
}

resource "routeros_snmp_community" "communities" {
  for_each = { for c in var.snmp_communities : c.name => c }

  name                    = each.value.name
  addresses               = each.value.addresses
  authentication_password = each.value.authentication_password
  authentication_protocol = each.value.authentication_protocol
  comment                 = each.value.comment != "" ? each.value.comment : null
  disabled                = each.value.disabled
  encryption_password     = each.value.encryption_password
  encryption_protocol     = each.value.encryption_protocol
  read_access             = each.value.read_access
  security                = each.value.security
  write_access            = each.value.write_access
}
