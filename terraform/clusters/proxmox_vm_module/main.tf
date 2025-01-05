# Local variable to remove dots from IPv4 address prefix
locals {
  base_vmid = replace(var.ipv4_address_prefix, ".", "")
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  count = var.cp_quantity
  name  = "${var.name_prefix}-controlplane-${count.index + 1}"

  # Assign provider and node_name based on index
  node_name = count.index % 3 == 1 ? "pve02" : count.index % 3 == 2 ? "pve03" : "pve01"
  
  vm_id         = "${local.base_vmid}${count.index + var.cp_octet_start}"
  description   = "Managed by Terraform"
  tags          = ["terraform", "ubuntu", "k8s-control-plane", "${var.name_prefix}"]

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    file_id      = var.file_id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.cp_disk_size
    file_format  = "raw"
  }

  cpu {
    cores   = var.cp_cpus
    sockets = 1
    numa    = true
    type    = "host"
  }

  memory {
    dedicated = var.cp_memory
  }

  agent {
    enabled = true
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = var.vlan_id
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ipv4_address_prefix}${count.index + var.cp_octet_start}/${var.ipv4_address_subnet}"
        gateway = var.ipv4_gateway
      }
      ipv6 {
        address = "${var.ipv6_address_prefix}${count.index + var.cp_octet_start}/${var.ipv6_address_subnet}"
        gateway = var.ipv6_gateway
      }
    }

    dns {
      servers   = var.dns_server
      domain    = var.dns_domain
    }
    
    datastore_id = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.ubuntu_cloud_init.id
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "std"
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  count = var.wkr_quantity
  name  = "${var.name_prefix}-worker-${count.index + 1}"

  # Assign provider and node_name based on index
  node_name = count.index % 3 == 1 ? "pve02" : count.index % 3 == 2 ? "pve03" : "pve01"
  
  vm_id       = "${local.base_vmid}${count.index + var.wkr_octet_start}"
  description = "Managed by Terraform"
  tags        = ["terraform", "ubuntu", "k8s-worker", "${var.name_prefix}"]

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    file_id      = var.file_id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.wkr_disk_size
    file_format  = "raw"
  }

  cpu {
    cores   = var.wkr_cpus
    sockets = 1
    numa    = true
    type    = "host"
  }

  memory {
    dedicated = var.wkr_memory
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    vlan_id = var.vlan_id
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ipv4_address_prefix}${count.index + var.wkr_octet_start}/${var.ipv4_address_subnet}"
        gateway = var.ipv4_gateway
      }
      ipv6 {
        address = "${var.ipv6_address_prefix}${count.index + var.wkr_octet_start}/${var.ipv6_address_subnet}"
        gateway = var.ipv6_gateway
      }
    }

    dns {
      servers   = var.dns_server
      domain    = var.dns_domain
    }
    
    datastore_id = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.ubuntu_cloud_init.id
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "std"
  }
}

resource "proxmox_virtual_environment_file" "ubuntu_cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve01"

  source_raw {
    data = <<EOF
#cloud-config

# Set the password for the ubuntu user and disable expiration
chpasswd:
  list: |
    ubuntu:ubuntu
    root:NewRootPassword  # Replace 'NewRootPassword' with the desired root password
  expire: false

# Install qemu-guest-agent for improved VM management
packages:
  - qemu-guest-agent

# Set timezone
timezone: America/Los_Angeles

# User configuration
users:
  - default
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    ssh-authorized-keys:
      - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}
    sudo: ALL=(ALL) NOPASSWD:ALL

# Configure root to allow SSH access with the same key
  - name: root
    ssh-authorized-keys:
      - ${trimspace("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com")}
    sudo: ALL=(ALL) NOPASSWD:ALL

# Enable root SSH access in SSH configuration
runcmd:
  - sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart ssh

# Reboot the VM after cloud-init completes
power_state:
    delay: now
    mode: reboot
    message: Rebooting after cloud-init completion
    condition: true
EOF

    file_name = "ubuntu.cloud-config.yaml"
  }
}
