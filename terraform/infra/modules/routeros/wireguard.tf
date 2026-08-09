resource "routeros_interface_wireguard" "interfaces" {
  for_each = { for w in var.wireguard_interfaces : w.name => w }

  name        = each.value.name
  comment     = each.value.comment != "" ? each.value.comment : null
  disabled    = each.value.disabled
  listen_port = each.value.listen_port
  mtu         = each.value.mtu
  private_key = each.value.private_key
}

resource "routeros_interface_wireguard_peer" "peers" {
  for_each = { for p in var.wireguard_peers : "${p.interface}-${p.name}" => p }

  interface             = each.value.interface
  name                   = each.value.name != "" ? each.value.name : null
  comment                = each.value.comment != "" ? each.value.comment : null
  disabled               = each.value.disabled
  public_key             = each.value.public_key
  preshared_key          = each.value.preshared_key
  allowed_address        = each.value.allowed_address
  endpoint_address       = each.value.endpoint_address != "" ? each.value.endpoint_address : null
  endpoint_port          = each.value.endpoint_port != "" ? each.value.endpoint_port : null
  persistent_keepalive   = each.value.persistent_keepalive != "" ? each.value.persistent_keepalive : null

  depends_on = [routeros_interface_wireguard.interfaces]
}
