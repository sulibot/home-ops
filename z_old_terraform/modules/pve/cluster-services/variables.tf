# --- Proxmox provider inputs (token preferred; fallback to user/pass)
#variable "pve_endpoint" {
#  type = string
#}

#variable "pve_api_token_id" {
#  type      = string
#  sensitive = true
#  default   = ""
#}

#variable "pve_api_token_secret" {
#  type      = string
#  sensitive = true
#  default   = ""
#}

#variable "pve_username" {
#  type    = string
#  default = ""
#}

#variable "pve_password" {
#  type      = string
#  sensitive = true
#  default   = ""
#}

# Nodes from your cluster (used to derive SDN zone node list and choose an SSH jump host)
variable "nodes" {
  type = list(object({
    ssh_host = string                 # e.g., "root@pve01"
    domains  = optional(list(string), [])
  }))
}

# SDN EVPN mesh input (zone-only via provider; VNet/Subnet optionally via pvesh)
#variable "sdn_evpn" {
#  type = object({
#    controller = string
#    clusters   = map(object({
#      enabled   = optional(bool, true)
#      vrf_vxlan = number
#      vnet_tag  = number
#      v4_cidr   = string
#      v6_cidr   = string
#      mtu       = number
#    }))
#  })
#}

# Optional: execute pvesh to create VNets/Subnets since provider v0.83.x lacks these resources
variable "configure_vnets" {
  type    = bool
  default = true
}

variable "primary_ssh_host" {
  type    = string
  default = "" # if empty, uses first nodes[0].ssh_host
}


# ===== variables.tf (add these) =====

# ACME directory selector or explicit URL.
# Accepts "production" | "staging" | full URL
variable "acme_directory" {
  type        = string
  description = "ACME directory: production, staging, or a custom directory URL."
  default     = "production"
}

# Friendly name for the ACME account (shown in Proxmox UI)
variable "acme_account_name" {
  type        = string
  description = "Name for the ACME account in Proxmox."
  default     = "letsencrypt"
}

# Contact email used to register the ACME account
variable "acme_contact_email" {
  type        = string
  description = "Contact email for ACME account registration."
}

# DNS plugin settings for Proxmox ACME
variable "dns_plugin" {
  description = "Proxmox ACME DNS plugin configuration."
  type = object({
    id               = string          # e.g., "cf" (the plugin name/id in Proxmox)
    api              = string          # e.g., "https://api.cloudflare.com/client/v4"
    data             = map(string)     # key/values expected by the plugin (token, zone-id, etc.)
    validation_delay = optional(number)
  })
}

# Whether to immediately order certs and restart pveproxy during apply
variable "order_on_apply" {
  type        = bool
  description = "If true, run 'pvenode acme cert order --force 1' and restart pveproxy on each node."
  default     = true
}
