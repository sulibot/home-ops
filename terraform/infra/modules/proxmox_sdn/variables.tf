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

variable "apply_sdn_config" {
  description = "Create the Proxmox SDN applier resource. Leave false for adoption/no-op plans; set true only when intentionally pushing SDN changes."
  type        = bool
  default     = false
}

variable "enable_underlay_fabric" {
  description = "Manage the OSPF underlay (mesh-link loopback reachability) via a PVE SDN Fabric instead of hand-rolled FRR. Prototype/opt-in - leave false until cutover is tested and approved."
  type        = bool
  default     = false
}

variable "fabric_ospf_prefix" {
  description = "Loopback address range for the OSPF underlay fabric (matches existing lo-infra addressing so node IPs are unchanged)."
  type        = string
  default     = "10.255.0.0/24"
}

variable "fabric_ospf_area" {
  description = "OSPF area for the underlay fabric"
  type        = string
  default     = "0.0.0.0"
}

variable "fabric_nodes" {
  description = "Per-node underlay fabric config: loopback IP (must fall within fabric_ospf_prefix) and the physical mesh-link interfaces to run OSPF on."
  type = map(object({
    ip              = string
    interface_names = set(string)
  }))
  default = {}
}

variable "vnets" {
  description = "Map of VNets to create with their configuration"
  type = map(object({
    alias      = string
    vxlan_id   = number
    subnet     = string
    gateway    = string
    subnet_v4  = optional(string)
    gateway_v4 = optional(string)
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
