resource "routeros_system_identity" "this" {
  count = var.system != null && var.system.identity != null ? 1 : 0
  name  = var.system.identity
}

resource "routeros_system_clock" "this" {
  count          = var.system != null && var.system.timezone != null ? 1 : 0
  time_zone_name = var.system.timezone
}

resource "routeros_system_ntp_client" "this" {
  count   = var.system != null ? 1 : 0
  enabled = true
  servers = var.system.ntp_servers
}

resource "routeros_system_ntp_server" "this" {
  count           = var.system != null && var.system.ntp_server_enabled ? 1 : 0
  enabled         = var.system.ntp_server_enabled
  manycast        = var.system.ntp_server_manycast
  multicast       = var.system.ntp_server_multicast
  use_local_clock = true
}

resource "routeros_ip_settings" "this" {
  count = var.ip_settings != null ? 1 : 0

  icmp_rate_limit      = var.ip_settings.icmp_rate_limit
  max_neighbor_entries = var.ip_settings.max_neighbor_entries
  send_redirects       = var.ip_settings.send_redirects
  tcp_syncookies       = var.ip_settings.tcp_syncookies
}

resource "routeros_ipv6_settings" "this" {
  count = var.ipv6_settings != null ? 1 : 0

  accept_redirects              = var.ipv6_settings.accept_redirects
  accept_router_advertisements  = var.ipv6_settings.accept_router_advertisements
  max_neighbor_entries          = var.ipv6_settings.max_neighbor_entries
}

resource "routeros_ip_service" "services" {
  for_each = { for s in var.ip_services : s.name => s }

  numbers     = each.key
  disabled    = each.value.disabled
  address     = each.value.address
  port        = each.value.port
  certificate = each.value.certificate
}
