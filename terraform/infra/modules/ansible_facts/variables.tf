variable "region" {
  description = "Region identifier (passed from root but not used)"
  type        = string
  default     = "home-lab"
}

variable "repo_root" {
  description = "Absolute path to the repo root (get_repo_root() from terragrunt), used to place network-facts.json at ansible/network-facts.json regardless of where terragrunt is invoked from"
  type        = string
}

variable "bgp_asn_base" {
  description = "Base ASN for cluster ASN calculation (network-infrastructure.hcl locals.bgp.asn_base)"
  type        = number
}

variable "bgp_remote_asn" {
  description = "PVE FRR AS that cluster nodes peer with upstream (network-infrastructure.hcl locals.bgp.remote_asn)"
  type        = number
}

variable "sdn_mtu" {
  description = "SDN zone vnet MTU (network-infrastructure.hcl locals.sdn.mtu)"
  type        = number
}

variable "sdn_vrf_vxlan" {
  description = "SDN zone VXLAN VNI (network-infrastructure.hcl locals.sdn.vrf_vxlan)"
  type        = number
}

variable "sdn_zone_id" {
  description = "SDN zone name (network-infrastructure.hcl locals.sdn.zone_id)"
  type        = string
}

variable "routeros" {
  description = "RouterOS edge router facts (network-infrastructure.hcl locals.routeros)"
  type = object({
    local_asn      = number
    router_id      = string
    loopback_ipv4  = string
    loopback_ipv6  = string
    pve_range_ipv6 = string
    pve_asn        = number
  })
}
