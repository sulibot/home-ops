variable "region" {
  description = "Region identifier (injected by root terragrunt)"
  type        = string
  default     = "home-lab"
}

variable "bgp" {
  description = "BGP instance and single dual-stack connection (PVE_FABRIC / EDGE)"
  type = object({
    instance_name     = string  # "PVE_FABRIC"
    local_asn         = number  # 4200000000
    router_id         = string  # "10.255.0.254"
    connection_name   = string  # "EDGE"
    pve_asn           = number  # 4200001000
    remote_range      = string  # "fd00:0:0:ffff::/64" — IPv6 listen range
    local_address     = string  # "fd00:0:0:ffff::fffe" — ROS loopback IPv6
    afi               = optional(string, "ip,ipv6")
    use_bfd           = optional(bool, true)
    hold_time         = optional(string, "30s")
    keepalive_time    = optional(string, "10s")
    redistribute      = optional(string, "connected,static,bgp")
    default_originate = optional(string, "always")
  })
}

variable "firewall_filter_rules" {
  description = "IP firewall filter rules. Order is preserved by list index — position 0 is first on device."
  type = list(object({
    comment              = optional(string, "")
    chain                = string
    action               = string
    disabled             = optional(bool, false)
    protocol             = optional(string)
    connection_state     = optional(string)
    in_interface_list    = optional(string)
    out_interface_list   = optional(string)
    src_address_list     = optional(string)
    dst_address_list     = optional(string)
    connection_nat_state = optional(string)
    hw_offload           = optional(bool)
    ipsec_policy         = optional(string)
  }))
  default = []
}

variable "firewall_nat_rules" {
  description = "IP firewall NAT rules."
  type = list(object({
    comment            = optional(string, "")
    chain              = string
    action             = string
    disabled           = optional(bool, false)
    out_interface_list = optional(string)
  }))
  default = []
}

variable "address_lists" {
  description = "Firewall address-list entries."
  type = list(object({
    list    = string
    address = string
    comment = optional(string, "")
  }))
  default = []
}

variable "interface_lists" {
  description = "Interface list names to manage (WAN, LAN, etc.)"
  type        = list(string)
  default     = []
}

variable "interface_list_members" {
  description = "Interface list member assignments."
  type = list(object({
    list      = string
    interface = string
  }))
  default = []
}

variable "dns_settings" {
  description = "Global DNS server settings (routeros_ip_dns singleton). Null = not managed."
  type = object({
    allow_remote_requests   = optional(bool, true)
    cache_max_ttl           = optional(string, "1d")
    max_concurrent_queries  = optional(number, 200)
    mdns_repeat_ifaces      = optional(set(string), [])
    query_server_timeout    = optional(string, "3s")
    query_total_timeout     = optional(string, "15s")
    servers                 = optional(list(string), [])
  })
  default = null
}

variable "system" {
  description = "System-level settings. Null = not managed."
  type = object({
    identity             = optional(string)
    timezone             = optional(string)
    ntp_servers          = optional(list(string), [])
    ntp_server_enabled   = optional(bool, false)
    ntp_server_manycast  = optional(bool, false)
    ntp_server_multicast = optional(bool, false)
  })
  default = null
}

variable "ip_settings" {
  description = "IPv4 stack settings (routeros_ip_settings singleton). Null = not managed."
  type = object({
    icmp_rate_limit      = optional(number)
    max_neighbor_entries = optional(number)
    send_redirects       = optional(bool)
    tcp_syncookies       = optional(bool)
  })
  default = null
}

variable "ipv6_settings" {
  description = "IPv6 stack settings (routeros_ipv6_settings singleton). Null = not managed."
  type = object({
    accept_redirects              = optional(string)  # "no" | "yes-if-forwarding-disabled"
    accept_router_advertisements  = optional(string)  # "no" | "yes" | "yes-if-forwarding-disabled"
    max_neighbor_entries          = optional(number)
  })
  default = null
}

variable "ip_services" {
  description = "Per-service access restrictions. Only listed services are managed."
  type = list(object({
    name        = string  # "ssh", "www", "www-ssl", "winbox", "ftp", "telnet", "api", "api-ssl"
    disabled    = optional(bool)
    address     = optional(string)
    port        = optional(number)
    certificate = optional(string)
  }))
  default = []
}

variable "ipv6_address_lists" {
  description = "IPv6 firewall address-list entries."
  type = list(object({
    list    = string
    address = string
    comment = optional(string, "")
  }))
  default = []
}

variable "ipv6_firewall_filter_rules" {
  description = "IPv6 firewall filter rules. Order is preserved by list index."
  type = list(object({
    comment            = optional(string, "")
    chain              = string
    action             = string
    disabled           = optional(bool, false)
    protocol           = optional(string)
    connection_state   = optional(string)
    in_interface_list  = optional(string)
    out_interface_list = optional(string)
    src_address_list   = optional(string)
    dst_address_list   = optional(string)
    src_address        = optional(string)
    dst_address        = optional(string)
    dst_port           = optional(string)
    hop_limit          = optional(string)
    ipsec_policy       = optional(string)
    log_prefix         = optional(string)
  }))
  default = []
}

variable "routing_filter_rules" {
  description = "BGP/routing filter rules."
  type = list(object({
    chain    = string
    rule     = string
    comment  = optional(string, "")
    disabled = optional(bool, false)
  }))
  default = []
}

variable "bfd_configurations" {
  description = "BFD session configurations."
  type = list(object({
    addresses  = set(string)
    disabled   = optional(bool, false)
    min_rx     = optional(string, "300ms")
    min_tx     = optional(string, "300ms")
    multiplier = optional(number, 3)
  }))
  default = []
}

variable "dns_records" {
  description = "Static DNS records. Do NOT include external-dns managed records (ttl=0s / k8s.* TXT) — they are managed by Kubernetes and must not be touched here."
  type = list(object({
    name     = string
    type     = optional(string, "A")  # "A", "AAAA", "TXT", "CNAME"
    address  = optional(string)       # for A / AAAA records
    text     = optional(string)       # for TXT records
    disabled = optional(bool, false)
    ttl      = optional(string, "5m")
    comment  = optional(string, "")
  }))
  default = []
}
