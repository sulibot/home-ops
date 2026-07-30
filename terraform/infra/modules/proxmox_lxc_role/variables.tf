variable "region" {
  type    = string
  default = "home-lab"
}

variable "proxmox" {
  description = "Proxmox storage defaults"
  type = object({
    datastore_id = string
    vm_datastore = string
  })
}

variable "template" {
  description = "LXC template source configuration"
  type = object({
    download  = bool
    url       = string
    file_name = string
    file_id   = string
  })
}

variable "dns_servers" {
  description = "DNS servers configured in container initialization"
  type        = list(string)
}

variable "containers" {
  description = "Container definitions keyed by logical name"
  type = map(object({
    vm_id         = number
    node_name     = string
    hostname      = string
    description   = string
    started       = optional(bool, true)
    start_on_boot = optional(bool, true)
    protection    = optional(bool, false)
    unprivileged  = optional(bool, false)
    tags          = optional(list(string), [])
    cpu_cores     = number
    memory_mb     = number
    swap_mb       = number
    disk_gb       = number
    bridge        = string
    vlan_id       = optional(number)
    firewall      = optional(bool, false)
    features = optional(object({
      nesting = optional(bool, true)
      keyctl  = optional(bool, true)
      mount   = optional(list(string), [])
    }), {})
    ipv4_address    = string
    ipv4_gateway    = string
    ipv6_address    = string
    ipv6_gateway    = string
    ssh_public_keys = optional(list(string), [])
    mount_points = optional(list(object({
      volume    = string
      size      = optional(string)
      path      = string
      backup    = optional(bool, false)
      shared    = optional(bool, true)
      replicate = optional(bool, false)
    })), [])
  }))
}

variable "provision" {
  description = "Optional post-create remote provisioning settings"
  type = object({
    enabled            = bool
    ssh_user           = string
    ssh_private_key    = string
    ssh_timeout        = string
    wait_for_cloudinit = bool
    commands           = list(string)
  })
  default = {
    enabled            = false
    ssh_user           = "root"
    ssh_private_key    = ""
    ssh_timeout        = "5m"
    wait_for_cloudinit = false
    commands           = []
  }
}
