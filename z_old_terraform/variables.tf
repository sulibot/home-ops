variable "pve_endpoint" {
  type        = string
  description = "The endpoint for the Proxmox API"
}

variable "pve_api_token_id" {
  type        = string
  description = "Proxmox API token ID"
}

variable "pve_api_token_secret" {
  type        = string
  description = "Proxmox API token secret"
}

variable "pve_username" {
  type        = string
  description = "Proxmox username"
}

variable "pve_password" {
  type        = string
  description = "Proxmox password"
}

variable "routeros_hosturl" {
  type        = string
  description = "RouterOS API IP or hostname URL"
}

variable "routeros_username" {
  type        = string
  description = "RouterOS API username"
}

variable "routeros_password" {
  type        = string
  description = "RouterOS API password"
  sensitive   = true
}