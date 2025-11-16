# live/clusters/cluster-101/variables.tf

variable "cluster_id" {
  description = "Numeric cluster ID"
  type        = number
}
variable "cluster_name" {
  description = "Cluster name"
  type        = string
}
variable "datastore_id" {
  description = "Proxmox datastore for VM disks"
  type        = string
}
variable "snippet_datastore_id" {
  description = "Proxmox datastore for cloud-init snippets"
  type        = string
}
variable "template_vmid" {
  description = "VMID for the template"
  type        = number
}
variable "cloudinit_template_file" {
  description = "Cloud-init template file path"
  type        = string
}
variable "frr_template_file" {
  description = "FRR template file path"
  type        = string
}
variable "control_plane" {
  description = "Control-plane group definition"
  type = object({
    role              = string
    role_id           = string
    cpu_count         = number
    memory_mb         = number
    instance_count    = number
    disk_size_gb      = number
    segment_start     = number
    k8s_vip_rise      = optional(number)
    k8s_vip_fall      = optional(number)
    k8s_vip_cooldown  = optional(number)
    pci_devices       = optional(map(string))
    enable_ipv4       = optional(bool, true)
    enable_ipv6       = optional(bool, true)
  })
}
variable "workers" {
  description = "Worker group definition"
  type = object({
    role              = string
    role_id           = string
    cpu_count         = number
    memory_mb         = number
    instance_count    = number
    disk_size_gb      = number
    segment_start     = number
    pci_devices       = optional(map(string))
    enable_ipv4       = optional(bool, true)
    enable_ipv6       = optional(bool, true)
  })
}

variable "pve_endpoint" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "pve_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
  sensitive   = true
}

variable "pve_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "pve_username" {
  description = "Proxmox API username"
  type        = string
}

variable "pve_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "routeros_hosturl" {
  description = "RouterOS API URL (e.g. https://10.255.255.254)"
  type        = string
}

variable "routeros_username" {
  description = "RouterOS API username"
  type        = string
}

variable "routeros_password" {
  description = "RouterOS API password"
  type        = string
  sensitive   = true
}

# ---------------------------
# Provider SSH variables
# ---------------------------

variable "pve_ssh_user" {
  description = "SSH username for uploading snippets to the node"
  type        = string
  default     = "root"
}

variable "pve_ssh_agent" {
  description = "Use ssh-agent for SSH auth"
  type        = bool
  default     = true
}

variable "pve_ssh_private_key" {
  description = "Private key contents for SSH auth (set null to use ssh-agent)"
  type        = string
  default     = null
  sensitive   = true
}