variable "group" {
  description = "All config for this group of nodes"
  type = object({
    role             = string
    role_id          = string
    cpu_count        = number
    memory_mb        = number
    instance_count   = number
    disk_size_gb     = number
    segment_start    = number
    k8s_vip_rise     = optional(number, 3)
    k8s_vip_fall     = optional(number, 3)
    k8s_vip_cooldown = optional(number, 10)
    pci_devices      = optional(map(string), {})
  })
  
  validation {
    condition     = var.group.instance_count >= 0 && var.group.instance_count <= 100
    error_message = "Instance count must be between 1 and 100."
  }
  
  validation {
    condition     = var.group.cpu_count >= 1 && var.group.cpu_count <= 64
    error_message = "CPU count must be between 1 and 64."
  }
  
  validation {
    condition     = var.group.memory_mb >= 512
    error_message = "Memory must be at least 512 MB."
  }
  
  validation {
    condition = contains(["control-plane", "worker", "storage"], var.group.role)
    error_message = "Role must be one of: control-plane, worker, storage."
  }
}

variable "cluster_id" {
  description = "Unique cluster identifier (1-255)"
  type        = number
  
  validation {
    condition     = var.cluster_id >= 1 && var.cluster_id <= 255
    error_message = "Cluster ID must be between 1 and 255."
  }
}

variable "cluster_name" {
  description = "Cluster name prefix"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be lowercase alphanumeric with hyphens, starting and ending with alphanumeric."
  }
}

variable "datastore_id"         { type = string }
variable "snippet_datastore_id" { type = string }
variable "template_vmid"        { type = number }
variable "cloudinit_template_file" { type = string }
variable "frr_template_file"       { type = string }

variable "routeros_hosturl" {
  description = "RouterOS API IP or hostname URL"
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

variable "indices" {
  description = "List of indices for instances"
  type        = list(string)
  default     = []
}

variable "enable_ipv4" {
  description = "Enable IPv4 addressing/DNS for VMs"
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Enable IPv6 addressing/DNS for VMs"
  type        = bool
  default     = true
}