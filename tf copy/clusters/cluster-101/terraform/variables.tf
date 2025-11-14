variable "pve_endpoint" {
  type        = string
  description = "Matches secrets.sops.yaml:pve_endpoint (e.g., https://pve01.example.com:8006/api2/json)"
}

variable "pve_api_token_id" {
  type        = string
  description = "Matches secrets.sops.yaml:pve_api_token_id"
  sensitive   = true
  default     = ""
}

variable "pve_api_token_secret" {
  type        = string
  description = "Matches secrets.sops.yaml:pve_api_token_secret"
  sensitive   = true
  default     = ""
}

variable "pve_username" {
  type        = string
  description = "Matches secrets.sops.yaml:pve_username (fallback when token auth is disabled)"
  default     = ""
}

variable "pve_password" {
  type        = string
  description = "Matches secrets.sops.yaml:pve_password (fallback when token auth is disabled)"
  sensitive   = true
  default     = ""
}

variable "pve_insecure" {
  type    = bool
  default = true
}

variable "pve_ssh_user" {
  type        = string
  description = "SSH username for uploading files to Proxmox nodes"
  default     = "root"
}

variable "pve_ssh_agent" {
  type        = bool
  description = "Use ssh-agent for uploading files to Proxmox nodes"
  default     = true
}

variable "pve_ssh_private_key" {
  type        = string
  description = "PEM-encoded private key for SSH uploads (leave null to rely on ssh-agent)"
  default     = null
  sensitive   = true
}

variable "pm_datastore_id" {
  type        = string
  description = "Where to upload image (e.g., local)"
}

variable "pm_vm_datastore" {
  type        = string
  description = "Datastore for VM disks (e.g., rdb-vm)"
}

variable "pm_snippets_datastore" {
  type        = string
  description = "Datastore for snippets/cloud-init"
}

variable "pm_node_primary" {
  type        = string
  description = "Primary node for uploads (e.g., pve01)"
}

variable "pm_nodes" {
  type        = list(string)
  description = "Round-robin nodes, e.g., [\"pve01\",\"pve02\",\"pve03\"]"
}

variable "vm_bridge_public" {
  type        = string
  description = "Bridge name for public network (e.g., vmbr0)"
}

variable "vm_vlan_public" {
  type    = number
  default = 0
}

variable "vm_bridge_mesh" {
  type        = string
  description = "Bridge name for mesh network (e.g., vmbr101)"
}

variable "vm_vlan_mesh" {
  type    = number
  default = 101
}

variable "vm_cpu_cores" {
  type    = number
  default = 4
}

variable "vm_memory_mb" {
  type    = number
  default = 8192
}

variable "vm_disk_gb" {
  type    = number
  default = 60
}

variable "talos_version" {
  type        = string
  description = "Talos release to build (e.g., v1.8.2)"
  default     = "v1.8.2"
}

variable "talos_platform" {
  type        = string
  description = "Talos factory platform"
  default     = "nocloud"
}

variable "talos_architecture" {
  type        = string
  description = "Talos CPU architecture"
  default     = "amd64"
}

variable "talos_extra_kernel_args" {
  type        = list(string)
  description = "Additional Talos kernel arguments"
  default     = []
}

variable "talos_system_extensions" {
  type        = list(string)
  description = "Talos official system extensions"
  default     = []
}

variable "talos_patches" {
  type        = any
  description = "Talos JSON patch operations"
  default     = []
}
