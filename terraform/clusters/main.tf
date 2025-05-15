terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.77.1"  # Use ~> for better version control
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1.1"
    }
    local = {
      source = "hashicorp/local"
    }
#    random = {
#      source  = "hashicorp/random"
#      version = "~> 3.6.2"
#    }
#    cloudinit = {
#      source  = "hashicorp/cloudinit"
#      version = "~> 2.3.4"
#    }
  }
}

resource "proxmox_virtual_environment_vm" "template" {
  name        = var.template_name
  vm_id       = var.template_vmid
  node_name   = var.node_name
  tags        = ["template", "base", "terraform"]
  description = "Terraform-built Debian 12 cloud-init template"
  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    file_id      = var.cloud_init_image_file_id
    interface    = "scsi0"
    iothread     = true
    size         = var.disk_size
    file_format  = "raw"
    cache        = "writeback"
    discard      = "on"
  }

  memory {
    dedicated = var.memory
    floating  = var.memory
  }

  cpu {
    sockets = 1
    cores   = var.cpus
    type    = "host"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv6 {
        dhcp = true
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    user_data_file_id = var.user_data_file_id
    datastore_id      = var.datastore_id
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes    = [tags]
    prevent_destroy   = true  # 🛡️ prevent accidental deletion
  }
}

resource "proxmox_virtual_environment_vm_template" "convert" {
  vm_id = proxmox_virtual_environment_vm.template.vm_id
}