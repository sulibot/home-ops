variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
}

variable "vm_name" {
  description = "VM hostname"
  type        = string
}

variable "proxmox" {
  description = "Proxmox connection details"
  type = object({
    node_name    = string
    datastore_id = string
    vm_datastore = string
  })
}

variable "vm_resources" {
  description = "VM resource allocation"
  type = object({
    cpu_cores = number
    memory_mb = number
    disk_gb   = number
  })
  default = {
    cpu_cores = 4
    memory_mb = 8192
    disk_gb   = 80
  }
}

variable "network" {
  description = "Network configuration"
  type = object({
    bridge       = string
    vlan_id      = optional(number)
    ipv4_address = string
    ipv4_gateway = string
    ipv6_address = optional(string)
    ipv6_gateway = optional(string)
    mtu          = optional(number, 1500)
    firewall     = optional(bool, false)
  })
}

variable "dns_servers" {
  description = "DNS server addresses"
  type        = list(string)
  default     = ["1.1.1.1", "1.0.0.1"]
}

variable "ssh_public_key" {
  description = "SSH public key for root user"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for provisioning (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "debian_version" {
  description = "Debian version"
  type        = string
  default     = "12"
}

variable "architecture" {
  description = "CPU architecture"
  type        = string
  default     = "amd64"
}

variable "debian_image_url" {
  description = "URL to Debian cloud image"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
}

variable "initial_packages" {
  description = "Initial packages to install via cloud-init"
  type        = list(string)
  default     = []
}

variable "setup_script" {
  description = "Optional setup script to run on first boot"
  type        = string
  default     = ""
}

variable "on_boot" {
  description = "Start VM on Proxmox boot"
  type        = bool
  default     = true
}

variable "vga_type" {
  description = "VGA hardware type"
  type        = string
  default     = "std"
}

variable "tags" {
  description = "VM tags"
  type        = list(string)
  default     = []
}
