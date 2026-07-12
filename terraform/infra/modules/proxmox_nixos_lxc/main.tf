# NixOS LXC on Proxmox. Deliberately provisioning-free: Terraform only
# creates the container from the NixOS proxmoxLXC template tarball; all
# system configuration comes from the nix/ flake via
#   nixos-rebuild switch --flake ./nix#<host> --target-host root@<host> --build-host root@<host>

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.98.0, < 1.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.4.0"
    }
  }
}

variable "region" {
  type    = string
  default = "home-lab"
}

variable "containers" {
  description = "NixOS LXC definitions, keyed by name"
  type = map(object({
    vm_id        = number
    node_name    = string
    hostname     = string
    description  = optional(string, "NixOS LXC")
    cpu_cores    = number
    memory_mb    = number
    swap_mb      = optional(number, 0)
    disk_gb      = number
    bridge       = string
    vlan_id      = optional(number)
    ipv4_address = string # CIDR
    ipv4_gateway = string
    ipv6_address = string # CIDR
    ipv6_gateway = string
    tags         = optional(list(string), ["nixos", "lxc"])
  }))
}

variable "proxmox" {
  type = object({
    vm_datastore = string
  })
}

variable "template_file_id" {
  description = "NixOS proxmoxLXC template tarball (see scripts/fetch-nixos-lxc-template.sh)"
  type        = string
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

resource "proxmox_virtual_environment_container" "this" {
  for_each = var.containers

  vm_id       = each.value.vm_id
  node_name   = each.value.node_name
  description = each.value.description
  tags        = each.value.tags

  # NixOS manages itself; PVE must not touch guest config.
  unprivileged = true

  operating_system {
    template_file_id = var.template_file_id
    type             = "unmanaged"
  }

  features {
    nesting = true
  }

  cpu {
    cores = each.value.cpu_cores
  }

  memory {
    dedicated = each.value.memory_mb
    swap      = each.value.swap_mb
  }

  disk {
    datastore_id = var.proxmox.vm_datastore
    size         = each.value.disk_gb
  }

  network_interface {
    name    = "eth0"
    bridge  = each.value.bridge
    vlan_id = each.value.vlan_id
  }

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = each.value.ipv4_gateway
      }
      ipv6 {
        address = each.value.ipv6_address
        gateway = each.value.ipv6_gateway
      }
    }

    dynamic "user_account" {
      for_each = length(var.ssh_public_keys) > 0 ? [1] : []
      content {
        keys = var.ssh_public_keys
      }
    }
  }

  started = true
}

output "containers" {
  value = {
    for name, ct in proxmox_virtual_environment_container.this :
    name => { id = ct.id, vm_id = ct.vm_id, node_name = ct.node_name }
  }
}
