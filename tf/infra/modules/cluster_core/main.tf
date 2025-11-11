terraform {
  # Backend configuration will be injected by Terragrunt
  backend "local" {}

  required_providers {
    external = { source = "hashicorp/external", version = "~> 2.2" }
    proxmox  = { source = "bpg/proxmox", version = "~> 0.83.0" }
    sops     = { source = "carlpett/sops", version = "~> 1.2.1" }
  }
}

variable "region" {
  type        = string
  description = "Region identifier (injected by root terragrunt)"
  default     = "home-lab"
}

variable "proxmox" {
  description = "Proxmox storage + node defaults"
  type = object({
    datastore_id = string
    vm_datastore = string
    node_primary = string
    nodes        = list(string)
  })
}

variable "vm_defaults" {
  description = "Default VM sizing"
  type = object({
    cpu_cores = number
    memory_mb = number
    disk_gb   = number
  })
}

variable "network" {
  description = "Default network wiring"
  type = object({
    bridge_public = string
    vlan_public   = number
    bridge_mesh   = string
    vlan_mesh     = number
  })
}

variable "nodes" {
  description = "Cluster nodes definition"
  type = list(object({
    name         = string
    vm_id        = optional(number)
    ip_suffix    = optional(number)
    ipv6_public  = optional(string)
    ipv4_public  = optional(string)
    node_name    = optional(string)
    cpu_cores    = optional(number)
    memory_mb    = optional(number)
    disk_gb      = optional(number)
    bridge_public = optional(string)
    vlan_public   = optional(number)
    bridge_mesh   = optional(string)
    vlan_mesh     = optional(number)
  }))
}

variable "talos_image_file_ids" {
  description = "Map of node name to uploaded Talos image file ID in Proxmox"
  type        = map(string)
}

locals {
  nodes = { for idx, node in var.nodes : node.name => merge(node, { index = idx }) }
  hypervisors = length(var.proxmox.nodes) > 0 ? var.proxmox.nodes : [var.proxmox.node_primary]
}

resource "proxmox_virtual_environment_vm" "nodes" {
  for_each = local.nodes

  vm_id     = try(each.value.vm_id, null)
  name      = each.value.name
  node_name = coalesce(
    try(each.value.node_name, null),
    local.hypervisors[ each.value.index % length(local.hypervisors) ],
    var.proxmox.node_primary
  )

  machine = "q35"
  bios    = "ovmf"

  cpu {
    sockets = 1
    cores   = coalesce(try(each.value.cpu_cores, null), var.vm_defaults.cpu_cores)
  }

  memory {
    dedicated = coalesce(try(each.value.memory_mb, null), var.vm_defaults.memory_mb)
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.proxmox.vm_datastore
    size         = coalesce(try(each.value.disk_gb, null), var.vm_defaults.disk_gb)
    # For shared storage, all nodes use the same file_id
    # For local storage, lookup by node name
    file_id      = length(var.talos_image_file_ids) == 1 ? values(var.talos_image_file_ids)[0] : var.talos_image_file_ids[coalesce(
      try(each.value.node_name, null),
      local.hypervisors[ each.value.index % length(local.hypervisors) ],
      var.proxmox.node_primary
    )]
  }

  network_device {
    bridge  = coalesce(try(each.value.bridge_mesh, null), var.network.bridge_mesh)
    vlan_id = coalesce(try(each.value.vlan_mesh, null), var.network.vlan_mesh)
  }

  network_device {
    bridge  = coalesce(try(each.value.bridge_public, null), var.network.bridge_public)
    vlan_id = coalesce(try(each.value.vlan_public, null), var.network.vlan_public)
  }

  agent { enabled = false }
  boot_order = ["scsi0"]
}

output "vm_names" {
  description = "List of VM names created"
  value       = keys(local.nodes)
}
