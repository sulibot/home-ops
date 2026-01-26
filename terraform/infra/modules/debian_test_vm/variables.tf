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

variable "dns_servers" {
  type        = list(string)
  description = "DNS server addresses"
  default     = ["fd00:0:0:ffff::53", "10.255.0.53"]
}

variable "debian_image_url" {
  type        = string
  description = "URL to Debian cloud image"
  default     = "https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-genericcloud-amd64-daily.qcow2"
}

variable "loopback" {
  description = "Loopback addresses for BGP router-id"
  type = object({
    ipv4 = string
    ipv6 = string
  })
  default = null
}

variable "frr_config" {
  description = "FRR BGP configuration"
  type = object({
    enabled           = bool
    local_asn         = number
    router_id         = string
    upstream_peer     = string
    upstream_asn      = number
    veth_enabled      = optional(bool, false)
    veth_namespace    = optional(string, "cilium")
    veth_ipv4_local   = optional(string, "169.254.101.2")
    veth_ipv4_remote  = optional(string, "169.254.101.1")
    veth_ipv6_local   = optional(string, "fd00:65:c111::2")
    veth_ipv6_remote  = optional(string, "fd00:65:c111::1")
  })
  default = null
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for cloud-init"
  default     = ""
}
