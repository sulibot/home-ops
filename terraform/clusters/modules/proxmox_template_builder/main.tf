# Try to find an existing VM template with the given VMID
data "proxmox_virtual_environment_vm" "existing_template" {
  count     = 1
  node_name = var.node_name
  vm_id     = var.template_vmid

  # Prevents failure if the VM does not exist
  lifecycle {
    ignore_errors = true
  }
}

# Create the base VM if it doesn't already exist
resource "proxmox_virtual_environment_vm" "template" {
  count       = data.proxmox_virtual_environment_vm.existing_template[0].id != "" ? 0 : 1
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
    ignore_changes = [tags]
  }
}

# Convert the base VM to a template if it was created
resource "proxmox_virtual_environment_vm_template" "convert" {
  count = length(proxmox_virtual_environment_vm.template) == 0 ? 0 : 1
  vm_id = proxmox_virtual_environment_vm.template[0].vm_id
}

# Optional output: helpful during plan/apply
output "template_status" {
  value = try(
    "Reusing existing template with VMID ${data.proxmox_virtual_environment_vm.existing_template[0].vm_id}",
    "Creating and converting new template ${var.template_name} (VMID ${var.template_vmid})"
  )
}
