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
    role             = string
    role_id          = string
    cpu_count        = number
    memory_mb        = number
    instance_count   = number
    disk_size_gb     = number
    segment_start    = number
    pci_devices      = optional(map(string))
    enable_ipv4      = optional(bool)
    enable_ipv6      = optional(bool)
  })
}

variable "workers" {
  description = "Worker group definition"
  type = object({
    role             = string
    role_id          = string
    cpu_count        = number
    memory_mb        = number
    instance_count   = number
    disk_size_gb     = number
    segment_start    = number
    pci_devices      = optional(map(string))
    enable_ipv4      = optional(bool)
    enable_ipv6      = optional(bool)
  })
}


variable "git_repo_root" {
  description = "The absolute path to the root of the Git repo, passed from Terragrunt"
  type        = string
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