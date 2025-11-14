terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.53.0"
    }
  }
}

locals {
  use_pve_api_token = var.pve_api_token_id != "" && var.pve_api_token_secret != ""
  proxmox_api_token = local.use_pve_api_token ? "${var.pve_api_token_id}=${var.pve_api_token_secret}" : null
  proxmox_username  = local.use_pve_api_token || var.pve_username == "" ? null : var.pve_username
  proxmox_password  = local.use_pve_api_token || var.pve_password == "" ? null : var.pve_password
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = local.proxmox_api_token
  username  = local.proxmox_username
  password  = local.proxmox_password
  insecure  = var.pve_insecure # true for labs without proper CA

  ssh {
    username    = var.pve_ssh_user
    agent       = var.pve_ssh_agent
    private_key = var.pve_ssh_private_key
    password    = var.pve_password != "" ? var.pve_password : null
  }
}

# Talos image factory invocation (HTTP-only, fast)
module "talos_image" {
  source            = "../../modules/talos_image_factory"
  version           = var.talos_version
  platform          = var.talos_platform
  architecture      = var.talos_architecture
  extra_kernel_args = var.talos_extra_kernel_args
  system_extensions = var.talos_system_extensions
  patches           = var.talos_patches
}

locals {
  talos_image_dir  = "${path.module}/../../images"
  talos_image_name = "${module.talos_image.image_id}.img"
  talos_image_path = "${local.talos_image_dir}/${local.talos_image_name}"
}

# Download Talos image locally (idempotent by factory artifact URL)
resource "terraform_data" "talos_image_download" {
  triggers_replace = {
    image_url = module.talos_image.image_url
  }

  provisioner "local-exec" {
    when    = create
    command = "mkdir -p ${local.talos_image_dir} && curl -L '${module.talos_image.image_url}' -o '${local.talos_image_path}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f '${local.talos_image_path}'"
  }
}

# Upload the Talos image to Proxmox (idempotent by content fingerprint)
resource "proxmox_virtual_environment_file" "talos_image" {
  content_type = "iso"
  datastore_id = var.pm_datastore_id
  node_name    = var.pm_node_primary
  source_file  = local.talos_image_path
  file_name    = local.talos_image_name

  depends_on = [terraform_data.talos_image_download]
}

# Example: define control plane and worker nodes
locals {
  cluster_id    = 101
  cluster_name  = "sol"
  cp_count      = 3
  wk_count      = 2
  base_name     = "${local.cluster_name}${local.cluster_id}"
  controlplanes = [for i in range(1, local.cp_count + 1) : format("%s-cp%02d", local.base_name, i)]
  workers       = [for i in range(1, local.wk_count + 1) : format("%s-wk%02d", local.base_name, i)]
  all_nodes     = concat(local.controlplanes, local.workers)
}

# Example VM definition module call(s) — swap to your actual module
# Below is a single resource loop (minimal) to illustrate
resource "proxmox_virtual_environment_vm" "nodes" {
  for_each = toset(local.all_nodes)

  name      = each.value
  node_name = var.pm_nodes[index(local.all_nodes, each.value) % length(var.pm_nodes)]

  # Basic VM hardware
  machine = "q35"
  bios    = "ovmf"
  cpu {
    cores   = var.vm_cpu_cores
    sockets = 1
  }
  memory {
    dedicated = var.vm_memory_mb
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.pm_vm_datastore
    size         = var.vm_disk_gb
    file_id      = proxmox_virtual_environment_file.talos_image.id
  }

  network_device {
    bridge  = var.vm_bridge_public # e.g., "vmbr0"
    vlan_id = var.vm_vlan_public
  }
  network_device {
    bridge  = var.vm_bridge_mesh # e.g., "vmbr101"
    vlan_id = var.vm_vlan_mesh
  }

  boot_order = ["scsi0"]
  agent { enabled = true }

  # Cloud-init
  initialization {
    datastore_id      = var.pm_snippets_datastore
    user_data_file_id = proxmox_virtual_environment_file.talos_image.id
    ip_config {
      ipv6 { address = "dhcp" }
      ipv4 { address = "dhcp" }
    }
  }
}

output "node_names" {
  value = local.all_nodes
}
