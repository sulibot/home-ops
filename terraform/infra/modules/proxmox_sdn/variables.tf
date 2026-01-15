variable "region" {
  description = "Infrastructure region (unused but required by root config)"
  type        = string
  default     = "home-lab"
}

variable "zone_id" {
  description = "SDN zone identifier"
  type        = string
  default     = "evpn-zone1"
}

variable "vrf_vxlan" {
  description = "VRF VXLAN ID for Layer 3 routing interconnect"
  type        = number
  default     = 4096

  validation {
    condition     = var.vrf_vxlan >= 1 && var.vrf_vxlan <= 16777215
    error_message = "VRF VXLAN ID must be between 1 and 16777215"
  }
}

variable "mtu" {
  description = "MTU for VNets (consider VXLAN overhead - typically 50 bytes)"
  type        = number
  default     = 1450
}

variable "disable_arp_nd_suppression" {
  description = "Disable ARP/ND suppression for EVPN (false = suppression enabled)"
  type        = bool
  default     = false
}

variable "nodes" {
  description = "Proxmox nodes participating in SDN"
  type        = set(string)
  default     = ["pve01", "pve02", "pve03"]
}

variable "advertise_subnets" {
  description = "Advertise subnets from the EVPN zone"
  type        = bool
  default     = true
}

variable "exit_nodes" {
  description = "Exit nodes for external connectivity (SNAT)"
  type        = set(string)
  default     = ["pve01", "pve02", "pve03"]
}

variable "primary_exit_node" {
  description = "Primary exit node for external connectivity"
  type        = string
  default     = "pve01"
}

variable "rt_import" {
  description = "Route target import value for VRF (e.g., for default route from RouterOS)"
  type        = string
  default     = "65000:1"
}

variable "vnets" {
  description = "Map of VNets to create with their configuration"
  type = map(object({
    alias       = string
    vxlan_id    = number
    subnet      = string
    gateway     = string
    subnet_v4   = optional(string)
    gateway_v4  = optional(string)
  }))

  validation {
    condition = alltrue([
      for k, v in var.vnets : v.vxlan_id >= 1 && v.vxlan_id <= 16777215
    ])
    error_message = "VXLAN IDs must be between 1 and 16777215"
  }
}

variable "delegated_prefixes" {
  description = "AT&T delegated IPv6 prefixes for GUA addressing (from DHCPv6-PD)"
  type = map(object({
    prefix  = string
    gateway = string
  }))
  default = {}
}
