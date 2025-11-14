terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.53.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.pm_api_url         # e.g., "https://pve01.sulibot.com:8006/api2/json"
  api_token = var.pm_api_token      # format: "terraform@pve!provider=xxxxx-..."
  insecure  = var.pm_insecure       # true for labs without proper CA
}

# Upload the base image to Proxmox (idempotent by content fingerprint)
resource "proxmox_virtual_environment_file" "debian_image" {
  content_type = "iso"
  datastore_id = var.pm_datastore_id   # e.g., "local"
  node_name    = var.pm_node_primary   # upload target node
  source_file  = "${path.module}/../../images/debian-12-generic-amd64.qcow2"
  file_name    = "debian-12-generic-amd64.qcow2"
}

# Example: define control plane and worker nodes
locals {
  cluster_id       = 102
  cluster_name     = "sol"
  cp_count         = 3
  wk_count         = 2
  base_name        = "${local.cluster_name}${local.cluster_id}"
  controlplanes    = [for i in range(1, local.cp_count + 1): format("%s-cp%02d", local.base_name, i)]
  workers          = [for i in range(1, local.wk_count + 1): format("%s-wk%02d", local.base_name, i)]
  all_nodes        = concat(local.controlplanes, local.workers)
}

# Example VM definition module call(s) — swap to your actual module
# Below is a single resource loop (minimal) to illustrate
resource "proxmox_virtual_environment_vm" "nodes" {
  for_each = toset(local.all_nodes)

  name      = each.value
  node_name = var.pm_nodes[ index(local.all_nodes, each.value) % length(var.pm_nodes) ]

  # Basic VM hardware
  machine   = "q35"
  bios      = "ovmf"
  cpu {
    cores = var.vm_cpu_cores
    sockets = 1
  }
  memory {
    dedicated = var.vm_memory_mb
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.pm_vm_datastore
    size         = var.vm_disk_gb
    file_id      = proxmox_virtual_environment_file.debian_image.id
  }

  network_device {
    bridge = var.vm_bridge_public   # e.g., "vmbr0"
    vlan_id = var.vm_vlan_public
  }
  network_device {
    bridge = var.vm_bridge_mesh     # e.g., "vmbr101"
    vlan_id = var.vm_vlan_mesh
  }

  boot_order = ["scsi0"]
  agent { enabled = true }

  # Cloud-init
  initialization {
    datastore_id = var.pm_snippets_datastore
    user_data_file_id = proxmox_virtual_environment_file.debian_image.id
    ip_config {
      ipv6 = "dhcp"
      ipv4 = "dhcp"
    }
  }
}

output "node_names" {
  value = local.all_nodes
}
