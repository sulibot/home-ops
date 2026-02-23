resource "routeros_ip_dns" "settings" {
  count = var.dns_settings != null ? 1 : 0

  allow_remote_requests   = var.dns_settings.allow_remote_requests
  cache_max_ttl           = var.dns_settings.cache_max_ttl
  max_concurrent_queries  = var.dns_settings.max_concurrent_queries
  mdns_repeat_ifaces      = length(var.dns_settings.mdns_repeat_ifaces) > 0 ? var.dns_settings.mdns_repeat_ifaces : null
  query_server_timeout    = var.dns_settings.query_server_timeout
  query_total_timeout     = var.dns_settings.query_total_timeout
  servers                 = length(var.dns_settings.servers) > 0 ? var.dns_settings.servers : null
}
