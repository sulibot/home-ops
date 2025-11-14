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
    ip_suffix    = number # Suffix for IP calculation
    # Optional overrides for specific nodes
    node_name    = optional(string)
    cpu_cores    = optional(number)
    memory_mb    = optional(number)
    disk_gb      = optional(number)
    vlan_public  = optional(number)
    vlan_mesh    = optional(number)
  }))
}

variable "ip_config" {
  description = "Configuration for generating node IP addresses"
  type = object({
    ipv6_prefix  = string
    ipv4_prefix  = string
    ipv6_gateway = string
    ipv4_gateway = string
    dns_servers  = list(string)
  })
}

variable "talos_image_file_id" {
  description = "The Proxmox file ID of the uploaded Talos image (e.g., local:iso/talos-....img)"
  type        = string
}

locals {
  # Generate full node configuration, including calculated IP addresses
  nodes = { for idx, node in var.nodes : node.name => merge(node, {
    index       = idx
    ipv6_public = format("%s%d", var.ip_config.ipv6_prefix, node.ip_suffix)
    ipv4_public = format("%s%d", var.ip_config.ipv4_prefix, node.ip_suffix)
  }) }

  hypervisors = length(var.proxmox.nodes) > 0 ? var.proxmox.nodes : [var.proxmox.node_primary]
}

resource "proxmox_virtual_environment_vm" "nodes" {
  for_each = local.nodes

  vm_id = try(each.value.vm_id, null)
  name  = each.value.name
  node_name = coalesce(
    try(each.value.node_name, null),
    local.hypervisors[each.value.index % length(local.hypervisors)],
    var.proxmox.node_primary
  )

  machine = "q35"
  bios    = "seabios" # SeaBIOS (legacy BIOS) works reliably with Talos nocloud ISO boot

  cpu {
    sockets = 1
    cores   = coalesce(try(each.value.cpu_cores, null), var.vm_defaults.cpu_cores)
    type    = "host" # Pass through host CPU flags for best performance.
  }

  memory {
    dedicated = coalesce(try(each.value.memory_mb, null), var.vm_defaults.memory_mb)
  }

  # Boot disk that Talos will install to
  disk {
    datastore_id = var.proxmox.vm_datastore
    file_format  = "raw"
    interface    = "scsi0"
    size         = coalesce(try(each.value.disk_gb, null), var.vm_defaults.disk_gb)
    cache        = "none"
    iothread     = true
    aio          = "io_uring"
  }

  # CD-ROM with Talos nocloud ISO
  cdrom {
    file_id   = var.talos_image_file_id
    interface = "ide0"
  }

  network_device {
    bridge  = coalesce(try(each.value.bridge_mesh, null), var.network.bridge_mesh)
    vlan_id = coalesce(try(each.value.vlan_mesh, null), var.network.vlan_mesh)
  }

  network_device {
    bridge  = coalesce(try(each.value.bridge_public, null), var.network.bridge_public)
    vlan_id = coalesce(try(each.value.vlan_public, null), var.network.vlan_public)
  }

  # Use Cloud-Init to inject a static IP into the Talos installer environment.
  # This makes the node reachable at a predictable IP for `talosctl apply-config`.
  # The permanent static IP in the machine config must match what's defined here.
  initialization {
    # Use the same datastore as the VM disk for Cloud-Init data.
    datastore_id = var.proxmox.vm_datastore
    ip_config {
      ipv4 {
        address = "${each.value.ipv4_public}/24"
        gateway = var.ip_config.ipv4_gateway
      }
      ipv6 {
        address = "${each.value.ipv6_public}/64"
        gateway = var.ip_config.ipv6_gateway
      }
    }
    dns {
      servers = var.ip_config.dns_servers
    }
  }

  agent {
    enabled = true # QEMU Guest Agent is useful for getting status and IPs
    trim    = true # Enable TRIM passthrough from the guest OS to the storage
  }

  # Boot from CD-ROM first (for Talos installation), then from disk
  boot_order = ["ide0", "scsi0"]
}

output "node_ips" {
  description = "Map of node names to their configured IP addresses"
  value = {
    for name, node in local.nodes : name => {
      ipv4 = node.ipv4_public
      ipv6 = node.ipv6_public
    }
  }
}

output "vm_names" {
  description = "List of VM names created"
  value = keys(local.nodes)
}
