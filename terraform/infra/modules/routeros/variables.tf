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
    in_interface         = optional(string)
    in_interface_list    = optional(string)
    out_interface        = optional(string)
    out_interface_list   = optional(string)
    src_address          = optional(string)
    src_address_list     = optional(string)
    dst_address          = optional(string)
    dst_address_list     = optional(string)
    dst_port             = optional(string)
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

variable "bridges" {
  description = "Bridge interfaces to manage."
  type = list(object({
    name           = string
    comment        = optional(string, "")
    admin_mac      = optional(string)
    auto_mac       = optional(bool)
    igmp_snooping  = optional(bool)
    pvid           = optional(number)
    protocol_mode  = optional(string)
    vlan_filtering = optional(bool)
    disabled       = optional(bool, false)
  }))
  default = []
}

variable "bridge_ports" {
  description = "Bridge port membership."
  type = list(object({
    bridge    = string
    interface = string
    comment   = optional(string, "")
    disabled  = optional(bool, false)
    pvid      = optional(number)
  }))
  default = []
}

variable "bridge_vlans" {
  description = "Bridge VLAN table rows."
  type = list(object({
    bridge   = string
    vlan_ids = set(string)
    tagged   = optional(set(string), [])
    untagged = optional(set(string), [])
    comment  = optional(string, "")
    disabled = optional(bool, false)
  }))
  default = []
}

variable "vlan_interfaces" {
  description = "VLAN interfaces."
  type = list(object({
    name      = string
    interface = string
    vlan_id   = number
    comment   = optional(string, "")
    disabled  = optional(bool, false)
  }))
  default = []
}

variable "ipv4_addresses" {
  description = "IPv4 addresses assigned to interfaces."
  type = list(object({
    address   = string
    interface = string
    network   = optional(string)
    comment   = optional(string, "")
    disabled  = optional(bool, false)
  }))
  default = []
}

variable "ipv4_pools" {
  description = "IPv4 pools."
  type = list(object({
    name      = string
    ranges    = list(string)
    next_pool = optional(string)
    comment   = optional(string, "")
  }))
  default = []
}

variable "ipv4_dhcp_options" {
  description = "IPv4 DHCP option definitions."
  type = list(object({
    name    = string
    code    = number
    value   = string
    comment = optional(string, "")
  }))
  default = []
}

variable "ipv4_dhcp_option_sets" {
  description = "IPv4 DHCP option sets."
  type = list(object({
    name    = string
    options = list(string)
    comment = optional(string, "")
  }))
  default = []
}

variable "ipv4_dhcp_servers" {
  description = "IPv4 DHCP servers."
  type = list(object({
    name                       = string
    interface                  = string
    address_pool               = optional(string)
    add_arp                    = optional(bool)
    address_lists              = optional(set(string), [])
    allow_dual_stack_queue     = optional(bool)
    always_broadcast           = optional(bool)
    authoritative              = optional(string)
    bootp_lease_time           = optional(string)
    bootp_support              = optional(string)
    client_mac_limit           = optional(number)
    comment                    = optional(string, "")
    conflict_detection         = optional(bool)
    delay_threshold            = optional(string)
    dhcp_option_set            = optional(string)
    disabled                   = optional(bool, false)
    dynamic_lease_identifiers  = optional(string)
    insert_queue_before        = optional(string)
    lease_script               = optional(string)
    lease_time                 = optional(string)
    parent_queue               = optional(string)
    relay                      = optional(string)
    src_address                = optional(string)
    support_broadband_tr101    = optional(bool)
    use_framed_as_classless    = optional(bool)
    use_radius                 = optional(string)
    use_reconfigure            = optional(bool)
  }))
  default = []
}

variable "ipv4_dhcp_server_networks" {
  description = "IPv4 DHCP server networks."
  type = list(object({
    address         = string
    gateway         = optional(string)
    dns_server      = optional(list(string), [])
    wins_server     = optional(list(string), [])
    ntp_server      = optional(list(string), [])
    caps_manager    = optional(list(string), [])
    domain          = optional(string)
    dhcp_option     = optional(list(string), [])
    dhcp_option_set = optional(string)
    dns_none        = optional(bool)
    ntp_none        = optional(bool)
    netmask         = optional(number)
    next_server     = optional(string)
    boot_file_name  = optional(string)
    comment         = optional(string, "")
  }))
  default = []
}

variable "ipv4_dhcp_server_leases" {
  description = "Static IPv4 DHCP leases and reservations."
  type = list(object({
    address               = string
    mac_address           = string
    server                = optional(string)
    client_id             = optional(string)
    address_lists         = optional(string)
    allow_dual_stack_queue = optional(bool)
    always_broadcast      = optional(bool)
    block_access          = optional(bool)
    comment               = optional(string, "")
    dhcp_option           = optional(string)
    dhcp_option_set       = optional(string)
    disabled              = optional(bool, false)
    insert_queue_before   = optional(string)
    lease_time            = optional(string)
    rate_limit            = optional(string)
    use_src_mac           = optional(bool)
  }))
  default = []
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

variable "ipv6_dhcp_clients" {
  description = "IPv6 DHCP clients / prefix delegation clients."
  type = list(object({
    interface                     = string
    request                       = list(string)
    comment                       = optional(string, "")
    disabled                      = optional(bool, false)
    accept_prefix_without_address = optional(bool)
    add_default_route             = optional(bool)
    allow_reconfigure             = optional(bool)
    check_gateway                 = optional(string)
    default_route_tables          = optional(set(string), [])
    pool_name                     = optional(string)
    pool_prefix_length            = optional(number)
    prefix_address_lists          = optional(set(string), [])
    script                        = optional(string)
    use_peer_dns                  = optional(bool)
    validate_server_duid          = optional(bool)
  }))
  default = []
}

variable "ipv6_addresses" {
  description = "IPv6 addresses to assign to interfaces."
  type = list(object({
    interface       = string
    address         = optional(string)
    from_pool       = optional(string)
    advertise       = optional(bool)
    auto_link_local = optional(bool)
    comment         = optional(string, "")
    disabled        = optional(bool, false)
    eui_64          = optional(bool)
    no_dad          = optional(bool)
  }))
  default = []
}

variable "ipv6_neighbor_discovery" {
  description = "IPv6 neighbor discovery / router advertisement settings per interface."
  type = list(object({
    interface                     = string
    advertise_dns                 = optional(bool)
    advertise_mac_address         = optional(bool)
    comment                       = optional(string, "")
    disabled                      = optional(bool, false)
    dns                           = optional(string)
    managed_address_configuration = optional(bool)
    mtu                           = optional(number)
    other_configuration           = optional(bool)
    ra_delay                      = optional(string)
    ra_interval                   = optional(string)
    ra_lifetime                   = optional(string)
    ra_preference                 = optional(string)
    reachable_time                = optional(string)
    retransmit_interval           = optional(string)
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

variable "ospf_instances" {
  description = "OSPF instances."
  type = list(object({
    name               = string
    version            = optional(number)
    vrf                = optional(string)
    router_id          = optional(string)
    redistribute       = optional(set(string), [])
    comment            = optional(string, "")
    disabled           = optional(bool, false)
    domain_id          = optional(string)
    domain_tag         = optional(number)
    in_filter_chain    = optional(string)
    mpls_te_address    = optional(string)
    mpls_te_area       = optional(string)
    originate_default  = optional(string)
    out_filter_chain   = optional(string)
    out_filter_select  = optional(string)
    routing_table      = optional(string)
  }))
  default = []
}

variable "ospf_areas" {
  description = "OSPF areas."
  type = list(object({
    name           = string
    instance       = string
    area_id        = optional(string)
    type           = optional(string)
    comment        = optional(string, "")
    default_cost   = optional(number)
    disabled       = optional(bool, false)
    no_summaries   = optional(bool)
    nssa_translate = optional(string)
  }))
  default = []
}

variable "ospf_interface_templates" {
  description = "OSPF interface templates."
  type = list(object({
    area                = string
    interfaces          = optional(set(string), [])
    networks            = optional(set(string), [])
    instance_id         = optional(number)
    type                = optional(string)
    cost                = optional(number)
    hello_interval      = optional(string)
    dead_interval       = optional(string)
    retransmit_interval = optional(string)
    transmit_delay      = optional(string)
    priority            = optional(number)
    passive             = optional(bool)
    use_bfd             = optional(bool)
    auth                = optional(string)
    auth_id             = optional(number)
    auth_key            = optional(string)
    authentication_key  = optional(string)
    comment             = optional(string, "")
    disabled            = optional(bool, false)
    prefix_list         = optional(string)
    vlink_neighbor_id   = optional(string)
    vlink_transit_area  = optional(string)
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

variable "snmp" {
  description = "RouterOS SNMP singleton settings."
  type = object({
    enabled            = optional(bool)
    contact            = optional(string)
    location           = optional(string)
    src_address        = optional(string)
    trap_interfaces    = optional(string)
    trap_target        = optional(set(string), [])
    vrf                = optional(string)
    engine_id_suffix   = optional(string)
  })
  default = null
}

variable "snmp_communities" {
  description = "RouterOS SNMP communities."
  type = list(object({
    name                     = string
    addresses                = optional(set(string), [])
    authentication_password  = optional(string)
    authentication_protocol  = optional(string)
    comment                  = optional(string, "")
    disabled                 = optional(bool, false)
    encryption_password      = optional(string)
    encryption_protocol      = optional(string)
    read_access              = optional(bool, true)
    security                 = optional(string, "none")
    write_access             = optional(bool, false)
  }))
  default = []
}
