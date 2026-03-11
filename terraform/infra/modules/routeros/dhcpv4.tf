resource "routeros_ip_pool" "pools" {
  for_each = { for p in var.ipv4_pools : p.name => p }

  name      = each.value.name
  ranges    = each.value.ranges
  next_pool = each.value.next_pool
  comment   = each.value.comment
}

resource "routeros_ip_dhcp_server" "servers" {
  for_each = { for s in var.ipv4_dhcp_servers : s.name => s }

  name                      = each.value.name
  interface                 = each.value.interface
  address_pool              = each.value.address_pool
  add_arp                   = each.value.add_arp
  address_lists             = each.value.address_lists
  allow_dual_stack_queue    = each.value.allow_dual_stack_queue
  always_broadcast          = each.value.always_broadcast
  authoritative             = each.value.authoritative
  bootp_lease_time          = each.value.bootp_lease_time
  bootp_support             = each.value.bootp_support
  client_mac_limit          = each.value.client_mac_limit
  comment                   = each.value.comment
  conflict_detection        = each.value.conflict_detection
  delay_threshold           = each.value.delay_threshold
  dhcp_option_set           = each.value.dhcp_option_set
  disabled                  = each.value.disabled
  dynamic_lease_identifiers = each.value.dynamic_lease_identifiers
  insert_queue_before       = each.value.insert_queue_before
  lease_script              = each.value.lease_script
  lease_time                = each.value.lease_time
  parent_queue              = each.value.parent_queue
  relay                     = each.value.relay
  src_address               = each.value.src_address
  support_broadband_tr101   = each.value.support_broadband_tr101
  use_framed_as_classless   = each.value.use_framed_as_classless
  use_radius                = each.value.use_radius
  use_reconfigure           = each.value.use_reconfigure
}

resource "routeros_ip_dhcp_server_network" "networks" {
  for_each = { for n in var.ipv4_dhcp_server_networks : n.address => n }

  address         = each.value.address
  gateway         = each.value.gateway
  dns_server      = each.value.dns_server
  wins_server     = each.value.wins_server
  ntp_server      = each.value.ntp_server
  caps_manager    = each.value.caps_manager
  domain          = each.value.domain
  dhcp_option     = each.value.dhcp_option
  dhcp_option_set = each.value.dhcp_option_set
  dns_none        = each.value.dns_none
  ntp_none        = each.value.ntp_none
  netmask         = each.value.netmask
  next_server     = each.value.next_server
  boot_file_name  = each.value.boot_file_name
  comment         = each.value.comment
}

resource "routeros_ip_dhcp_server_lease" "leases" {
  for_each = { for l in var.ipv4_dhcp_server_leases : l.address => l }

  address                 = each.value.address
  mac_address             = each.value.mac_address
  server                  = each.value.server
  client_id               = each.value.client_id
  address_lists           = each.value.address_lists
  allow_dual_stack_queue  = each.value.allow_dual_stack_queue
  always_broadcast        = each.value.always_broadcast
  block_access            = each.value.block_access
  comment                 = each.value.comment
  dhcp_option             = each.value.dhcp_option
  dhcp_option_set         = each.value.dhcp_option_set
  disabled                = each.value.disabled
  insert_queue_before     = each.value.insert_queue_before
  lease_time              = each.value.lease_time
  rate_limit              = each.value.rate_limit
  use_src_mac             = each.value.use_src_mac
}
