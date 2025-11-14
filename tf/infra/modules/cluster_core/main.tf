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

variable "cluster_id" {
  type        = number
  description = "The unique ID for the cluster, used for IP address calculations."
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
    public_mtu    = optional(number, 1500)
    mesh_mtu      = optional(number, 1500)
  })
}

variable "nodes" {
  description = "Cluster nodes definition"
  type = list(object({
    name      = string
    vm_id     = optional(number)
    ip_suffix = number # Suffix for IP calculation
    # Optional overrides for specific nodes
    node_name   = optional(string)
    cpu_cores   = optional(number)
    memory_mb   = optional(number)
    disk_gb     = optional(number)
    vlan_public = optional(number)
    vlan_mesh   = optional(number)
    public_mtu  = optional(number)
    mesh_mtu    = optional(number)
  }))
}

variable "ip_config" {
  description = "Configuration for generating node IP addresses"
  type = object({
    mesh = object({
      ipv6_prefix  = string
      ipv4_prefix  = string
      ipv6_gateway = optional(string)
      ipv4_gateway = optional(string)
    })
    public = object({
      ipv6_prefix  = string
      ipv4_prefix  = string
      ipv6_gateway = optional(string)
      ipv4_gateway = optional(string)
    })
    dns_servers = list(string)
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
    mesh_ipv6   = format("%s%d", var.ip_config.mesh.ipv6_prefix, node.ip_suffix)
    mesh_ipv4   = format("%s%d", var.ip_config.mesh.ipv4_prefix, node.ip_suffix)
    public_ipv6 = format("%s%d", var.ip_config.public.ipv6_prefix, node.ip_suffix)
    public_ipv4 = format("%s%d", var.ip_config.public.ipv4_prefix, node.ip_suffix)
  }) }

  hypervisors = length(var.proxmox.nodes) > 0 ? var.proxmox.nodes : [var.proxmox.node_primary]

  # ===================================================================
  # Kubernetes Network CIDRs
  # ===================================================================
  k8s_cidrs = {
    "101" = {
      pods_ipv4          = "10.101.0.0/16"
      pods_ipv6          = "fd00:101:1::/60"
      services_ipv4      = "10.101.96.0/20"
      services_ipv6      = "fd00:101:96::/108"
      loadbalancers_ipv4 = "10.101.27.0/24"
      loadbalancers_ipv6 = "fd00:101:1b::/120"
    },
    "102" = {
      pods_ipv4          = "10.102.0.0/16"
      pods_ipv6          = "fd00:102:1::/60"
      services_ipv4      = "10.102.96.0/20"
      services_ipv6      = "fd00:102:96::/108"
      loadbalancers_ipv4 = "10.102.27.0/24"
      loadbalancers_ipv6 = "fd00:102:1b::/120"
    },
    "103" = {
      pods_ipv4          = "10.103.0.0/16"
      pods_ipv6          = "fd00:103:1::/60"
      services_ipv4      = "10.103.96.0/20"
      services_ipv6      = "fd00:103:96::/108"
      loadbalancers_ipv4 = "10.103.27.0/24"
      loadbalancers_ipv6 = "fd00:103:1b::/120"
    }
  }

  # Selects the appropriate network configuration based on the var.cluster_id
  k8s_network_config = lookup(local.k8s_cidrs, tostring(var.cluster_id), {})
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

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "ovmf" # OVMF (UEFI) is the modern standard and preferred for Talos.

  # An EFI disk is required for UEFI boot. It stores the boot entries.
  # This disk should be on reliable, non-replicated storage if possible,
  # but using the same as the VM disk is also fine.
  efi_disk {
    datastore_id = var.proxmox.vm_datastore
    file_format  = "raw"
  }

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

  # net0 (eth0): Mesh network (Talos primary)
  network_device {
    bridge  = coalesce(try(each.value.bridge_mesh, null), var.network.bridge_mesh)
    vlan_id = coalesce(try(each.value.vlan_mesh, null), var.network.vlan_mesh)
    mtu     = try(each.value.mesh_mtu, var.network.mesh_mtu)
  }

  # net1 (eth1): Public/egress network
  network_device {
    bridge  = coalesce(try(each.value.bridge_public, null), var.network.bridge_public)
    vlan_id = coalesce(try(each.value.vlan_public, null), var.network.vlan_public)
    mtu     = try(each.value.public_mtu, var.network.public_mtu)
  }

  # Use Cloud-Init to inject a static IP into the Talos installer environment.
  # This makes the node reachable at a predictable IP for `talosctl apply-config`.
  # The permanent static IP in the machine config must match what's defined here.
  initialization {
    # Use the same datastore as the VM disk for Cloud-Init data.
    datastore_id = var.proxmox.vm_datastore

    # Mesh network (net0)
    ip_config {
      ipv4 {
        address = "${each.value.mesh_ipv4}/24"
        gateway = try(var.ip_config.mesh.ipv4_gateway, null)
      }
      ipv6 {
        address = "${each.value.mesh_ipv6}/64"
        gateway = try(var.ip_config.mesh.ipv6_gateway, null)
      }
    }

    # Public network (net1)
    ip_config {
      ipv4 {
        address = "${each.value.public_ipv4}/24"
        gateway = try(var.ip_config.public.ipv4_gateway, null)
      }
      ipv6 {
        address = "${each.value.public_ipv6}/64"
        gateway = try(var.ip_config.public.ipv6_gateway, null)
      }
    }

    dns {
      servers = var.ip_config.dns_servers
    }
  }

  agent {
    # The default Talos image does not include the QEMU Guest Agent.
    # Setting enabled = true will cause Terraform to wait for a long timeout.
    # We disable it to allow for fast VM creation.
    # The long-term solution, if guest agent functionality is desired,
    # is to build a custom Talos image with the `qemu-guest-agent` extension
    # using the Talos Image Factory.
    enabled = false
    trim    = true
  }

  # Boot from CD-ROM first (for Talos installation), then from disk
  boot_order = ["ide0", "scsi0"]
}

output "node_ips" {
  description = "Map of node names to their configured IP addresses"
  value = {
    for name, node in local.nodes : name => {
      mesh_ipv4   = node.mesh_ipv4
      mesh_ipv6   = node.mesh_ipv6
      public_ipv4 = node.public_ipv4
      public_ipv6 = node.public_ipv6
    }
  }
}

output "vm_names" {
  description = "List of VM names created"
  value       = keys(local.nodes)
}

output "talhelper_env" {
  description = "A map structured for generating a talenv.yaml file"
  value = { for n in local.nodes : n.name => {
    # Use the mesh network IP for Talos control plane communication
    ipAddress = n.mesh_ipv4
    hostname  = n.name
    # Determine the node role based on its name prefix
    controlPlane = substr(n.name, 4, 2) == "cp"
    # You can add other node-specific values here if needed
    # installDisk = "/dev/sda"
  } }
}

output "k8s_network_config" {
  description = "The Kubernetes network CIDRs for the current cluster."
  value       = local.k8s_network_config
}
