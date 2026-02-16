terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.89.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
    sops    = { source = "carlpett/sops", version = "~> 1.3.0" }
  }
}

locals {
  # Debian cloud image filename
  image_filename = "debian-${var.debian_version}-generic-${var.architecture}.qcow2"

  # Cloud-init user data
  user_data = templatefile("${path.module}/templates/cloud-init-user-data.yaml.tpl", {
    hostname         = var.vm_name
    ssh_public_key   = var.ssh_public_key
    initial_packages = var.initial_packages
    setup_script     = var.setup_script
  })

  # Cloud-init network config
  network_config = templatefile("${path.module}/templates/cloud-init-network.yaml.tpl", {
    network      = var.network
    dns_servers  = var.dns_servers
  })
}

# Download Debian cloud image to Proxmox
resource "proxmox_virtual_environment_download_file" "debian_image" {
  content_type = "import"
  datastore_id = var.proxmox.datastore_id
  node_name    = var.proxmox.node_name
  url          = var.debian_image_url
  file_name    = local.image_filename

  lifecycle {
    ignore_changes = [url]
  }
}

# Cloud-init user data snippet
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = var.proxmox.datastore_id
  node_name    = var.proxmox.node_name

  source_raw {
    data      = local.user_data
    file_name = "cloud-init-user-data-${var.vm_name}.yml"
  }
}

# Cloud-init network config snippet
resource "proxmox_virtual_environment_file" "cloud_init_network" {
  content_type = "snippets"
  datastore_id = var.proxmox.datastore_id
  node_name    = var.proxmox.node_name

  source_raw {
    data      = local.network_config
    file_name = "cloud-init-network-${var.vm_name}.yml"
  }
}

# Debian VM
resource "proxmox_virtual_environment_vm" "debian" {
  depends_on = [
    proxmox_virtual_environment_download_file.debian_image,
    proxmox_virtual_environment_file.cloud_init_user_data,
    proxmox_virtual_environment_file.cloud_init_network
  ]

  vm_id     = var.vm_id
  name      = var.vm_name
  node_name = var.proxmox.node_name

  started         = true
  stop_on_destroy = true
  on_boot         = var.on_boot

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "ovmf"

  efi_disk {
    datastore_id = var.proxmox.vm_datastore
    file_format  = "raw"
  }

  cpu {
    sockets = 1
    cores   = var.vm_resources.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = var.vm_resources.memory_mb
  }

  # Boot disk - clone from cloud image
  disk {
    datastore_id = var.proxmox.vm_datastore
    file_id      = proxmox_virtual_environment_download_file.debian_image.id
    interface    = "scsi0"
    size         = var.vm_resources.disk_gb
    cache        = "none"
    iothread     = true
    aio          = "io_uring"
  }

  # Network interface
  network_device {
    bridge   = var.network.bridge
    vlan_id  = var.network.vlan_id
    mtu      = var.network.mtu
    firewall = var.network.firewall
  }

  # Cloud-init configuration
  initialization {
    datastore_id = var.proxmox.vm_datastore

    user_data_file_id    = proxmox_virtual_environment_file.cloud_init_user_data.id
    network_data_file_id = proxmox_virtual_environment_file.cloud_init_network.id
  }

  agent {
    enabled = true
    trim    = true
  }

  vga {
    type = var.vga_type
  }

  boot_order = ["scsi0"]

  tags = concat(["debian"], var.tags)
}
