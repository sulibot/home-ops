resource "routeros_ipv6_address" "static_addresses" {
  for_each = { for a in var.ipv6_addresses : "${a.interface}-${a.address}" => a if a.from_pool == null }

  interface       = each.value.interface
  address         = each.value.address
  advertise       = each.value.advertise
  auto_link_local = each.value.auto_link_local
  comment         = each.value.comment != "" ? each.value.comment : null
  disabled        = each.value.disabled
  eui_64          = each.value.eui_64
  no_dad          = each.value.no_dad
}

resource "routeros_ipv6_address" "pool_addresses" {
  for_each = { for a in var.ipv6_addresses : "${a.interface}-${a.from_pool}" => a if a.from_pool != null }

  interface       = each.value.interface
  address         = each.value.address
  from_pool       = each.value.from_pool
  advertise       = each.value.advertise
  auto_link_local = each.value.auto_link_local
  comment         = each.value.comment != "" ? each.value.comment : null
  disabled        = each.value.disabled
  eui_64          = each.value.eui_64
  no_dad          = each.value.no_dad

  lifecycle {
    ignore_changes = [address]
  }
}

resource "routeros_ipv6_neighbor_discovery" "interfaces" {
  for_each = { for nd in var.ipv6_neighbor_discovery : nd.interface => nd }

  interface                     = each.value.interface
  advertise_dns                 = each.value.advertise_dns
  advertise_mac_address         = each.value.advertise_mac_address
  comment                       = each.value.comment != "" ? each.value.comment : null
  disabled                      = each.value.disabled
  dns                           = each.value.dns
  managed_address_configuration = each.value.managed_address_configuration
  mtu                           = each.value.mtu
  other_configuration           = each.value.other_configuration
  ra_delay                      = each.value.ra_delay
  ra_interval                   = each.value.ra_interval
  ra_lifetime                   = each.value.ra_lifetime
  ra_preference                 = each.value.ra_preference
  reachable_time                = each.value.reachable_time
  retransmit_interval           = each.value.retransmit_interval

  # RouterOS often omits unspecified values; drop them to avoid persistent null drift.
  ___drop_val___ = "mtu,hop-limit,reachable-time,retransmit-interval"
}
