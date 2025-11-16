# --- Proxmox auth ---
variable "pve_endpoint" {
  type = string
}
variable "pve_api_token_id" {
  type      = string
  sensitive = true
  default   = ""
}
variable "pve_api_token_secret" {
  type      = string
  sensitive = true
  default   = ""
}
variable "pve_username" {
  type    = string
  default = ""
}
variable "pve_password" {
  type      = string
  sensitive = true
  default   = ""
}

# Cluster nodes (names must match PVE node names; ssh_host for running pvesh remotely)
variable "nodes" {
  type = list(object({
    name     = string   # e.g., "pve01"
    ssh_host = string   # e.g., "root@pve01"
  }))
}

# If empty, we’ll run controller setup on the first nodes[0].ssh_host
variable "primary_ssh_host" {
  type    = string
  default = ""
}

# --- SDN EVPN controller ---
variable "sdn_controller" {
  type = object({
    id     = string
    asn    = number
    peers  = list(string)   # for peer model, set at least one
    fabric = optional(string)
  })
}

# --- SDN EVPN zones per "cluster id" (for provider resource) ---
variable "sdn_evpn_clusters" {
  type = map(object({
    vrf_vxlan = number        # e.g., 100, 101
    mtu       = number        # e.g., 8950
  }))
}

variable "configure_zones" {
  type    = bool
  default = true
}

# --- VNets/Subnets per "cluster id" (handled via pvesh) ---
variable "sdn_clusters" {
  type = map(object({
    vnet_tag = number         # L2 VNI/tag for the VNet
    v4_cidr  = string         # e.g., "10.10.100.0/24"
    v6_cidr  = string         # e.g., "fc00:100::/64"
  }))
}

variable "configure_vnets" {
  type    = bool
  default = true
}

# Fabric name (unused when configure_fabric = false)
variable "sdn_fabric_name" {
  type    = string
  default = "mesh"
}

# NEW: toggle fabric creation (peer model => false)
variable "configure_fabric" {
  type    = bool
  default = false
}
