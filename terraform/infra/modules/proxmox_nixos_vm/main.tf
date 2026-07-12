# NixOS VM on Proxmox. Terraform boots a throwaway Debian cloud image with
# SSH access; nixos-anywhere then kexecs the NixOS installer over SSH,
# partitions per the host's disko layout, and installs the flake config -
# building on the target (--build-on-remote), so no local x86_64 builder is
# needed. After first install:
#   nixos-rebuild switch --flake ./nix#<host> --target-host root@<host> --build-host root@<host>
#
# First install (run once per VM, after terraform creates it):
#   nix run github:nix-community/nixos-anywhere -- \
#     --flake ./nix#<host> --build-on-remote root@<bootstrap-ip>

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

variable "vm_name" { type = string }
variable "vm_id" { type = number }

variable "proxmox" {
  type = object({
    node_name    = string
    datastore_id = string # snippets/cloud-init
    vm_datastore = string # disks
  })
}

variable "vm_resources" {
  type = object({
    cpu_cores = number
    memory_mb = number
    disk_gb   = number
  })
}

variable "network" {
  type = object({
    bridge       = string
    vlan_id      = optional(number)
    mtu          = optional(number, 1500)
    ipv4_address = string # CIDR - used by the bootstrap OS; NixOS re-declares it
    ipv4_gateway = string
  })
}

variable "bootstrap_image_file_id" {
  description = "Cloud image the VM boots before nixos-anywhere takes over"
  type        = string
  default     = "resources:import/debian-trixie-cloud-amd64.qcow2"
}

variable "ssh_public_key" { type = string }

resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = var.proxmox.datastore_id
  node_name    = var.proxmox.node_name

  source_raw {
    file_name = "cloud-init-user-data-${var.vm_name}.yml"
    data      = <<-EOT
      #cloud-config
      hostname: ${var.vm_name}-bootstrap
      disable_root: false
      users:
        - name: root
          ssh_authorized_keys:
            - ${var.ssh_public_key}
    EOT
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  vm_id       = var.vm_id
  name        = var.vm_name
  node_name   = var.proxmox.node_name
  description = "NixOS VM (installed via nixos-anywhere; configured by nix/ flake)"
  tags        = ["nixos", "vm"]

  started         = true
  on_boot         = true
  stop_on_destroy = true

  cpu {
    cores = var.vm_resources.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_resources.memory_mb
  }

  disk {
    datastore_id = var.proxmox.vm_datastore
    file_id      = var.bootstrap_image_file_id
    interface    = "virtio0"
    size         = var.vm_resources.disk_gb
  }

  network_device {
    bridge  = var.network.bridge
    vlan_id = var.network.vlan_id
    mtu     = var.network.mtu
    model   = "virtio"
  }

  serial_device {}

  agent {
    enabled = false # bootstrap OS has no agent; NixOS enables qemuGuest later
  }

  initialization {
    datastore_id      = var.proxmox.vm_datastore
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id

    ip_config {
      ipv4 {
        address = var.network.ipv4_address
        gateway = var.network.ipv4_gateway
      }
    }
  }

  lifecycle {
    # nixos-anywhere wipes the disk; never let TF "fix" the image afterwards
    ignore_changes = [disk[0].file_id, initialization]
  }
}

output "vm_id" { value = proxmox_virtual_environment_vm.this.vm_id }
output "bootstrap_ipv4" { value = split("/", var.network.ipv4_address)[0] }
output "install_command" {
  value = "nix run github:nix-community/nixos-anywhere -- --flake ./nix#${var.vm_name} --build-on-remote root@${split("/", var.network.ipv4_address)[0]}"
}
