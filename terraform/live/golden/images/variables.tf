// live/golden/images/variables.tf

variable "pve_endpoint" {
  type        = string
  description = "Proxmox API endpoint"
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
  sensitive   = true
}

# ---- SSH vars used by provider.ssh ----
variable "pve_ssh_user" {
  type        = string
  description = "SSH username for uploads to Proxmox nodes"
  # Keep null default since provider.tf uses coalesce(var.pve_ssh_user, "root")
  default     = null
}

variable "pve_ssh_agent" {
  type        = bool
  description = "Use local ssh-agent for authentication"
  default     = true
}

variable "pve_ssh_private_key" {
  type        = string
  description = "PEM private key contents to use for SSH (optional if using agent)"
  sensitive   = true
  default     = null
}

variable "images" {
  description = "Map of images with paths, file names, and optional checksums"
  type = map(object({
    path      = string
    file_name = optional(string)
    checksum  = optional(string)
  }))
}

variable "datastore_id" {
  type        = string
  description = "Proxmox datastore to store the images"
}

variable "node_name" {
  type        = string
  description = "Proxmox node name for resource placement"
}
