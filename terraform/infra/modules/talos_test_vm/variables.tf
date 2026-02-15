variable "region" {
  type        = string
  description = "Region identifier (injected by root terragrunt)"
  default     = "home-lab"
}

variable "vm_name" {
  type        = string
  description = "VM hostname"
}

variable "vm_id" {
  type        = number
  description = "Proxmox VM ID"
  default     = null
}

variable "proxmox" {
  description = "Proxmox configuration"
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
    cpu_cores = 2
    memory_mb = 2048
    disk_gb   = 20
  }
}

variable "network" {
  description = "Network configuration"
  type = object({
    bridge       = string
    mtu          = optional(number, 1450)
    ipv4_address = string
    ipv4_netmask = optional(string, "255.255.255.0")
    ipv4_gateway = string
    ipv6_address = string
    ipv6_prefix  = optional(number, 64)
    ipv6_gateway = string
  })
}

variable "loopback" {
  description = "Loopback addresses for BGP router-id"
  type = object({
    ipv4 = string
    ipv6 = string
  })
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS server addresses"
  default     = ["fd00:0:0:ffff::53", "10.255.0.53"]
}

variable "bgp_config" {
  description = "BGP configuration for BIRD2"
  type = object({
    local_asn     = number
    router_id     = string
    upstream_peer = string
    upstream_asn  = number
  })
}

variable "talos_image_file_id" {
  description = "Proxmox file ID for Talos nocloud ISO (e.g., resources:iso/talos-....iso)"
  type        = string
}

variable "talos_version" {
  description = "Talos version (e.g., v1.12.1)"
  type        = string
  default     = "v1.12.1"
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g., 1.34.1)"
  type        = string
  default     = "1.34.1"
}

variable "install_disk" {
  description = "Disk device for Talos installation"
  type        = string
  default     = "/dev/sda"
}

variable "installer_image" {
  description = "Custom Talos installer image with extensions"
  type        = string
  default     = ""
}

variable "system_extensions" {
  description = "List of Talos system extension images"
  type        = list(string)
  default     = []
}

variable "kernel_args" {
  description = "Extra kernel arguments for Talos"
  type        = list(string)
  default     = []
}

variable "gobgp_image" {
  description = "GoBGP container image for Cilium simulation"
  type        = string
  default     = "ghcr.io/osrg/gobgp:v3.31.0"
}
