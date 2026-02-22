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
