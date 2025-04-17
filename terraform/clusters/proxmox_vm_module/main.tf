# Local variable to derive base VM ID from IPv4 address prefix
locals {
  base_vmid = replace(var.ipv4_address_prefix, ".", "")
  ssh_hosts = {
    pve01 = "fd00:255::1"
    pve02 = "fd00:255::2"
    pve03 = "fd00:255::3"
  }
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  count = var.cp_quantity
  name  = "${var.name_prefix}-controlplane-${count.index + 1}"

  # Distribute VMs across nodes based on index
  node_name = count.index % 3 == 1 ? "pve02" : count.index % 3 == 2 ? "pve03" : "pve01"

  vm_id = "${var.vlan_id}${format("%04d", count.index + var.cp_octet_start)}"
  description   = "Managed by Terraform"
  tags          = ["debian", "k8s-control-plane", "${var.name_prefix}", "terraform"]

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    file_id      = var.file_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    cache        = "writeback"
    size         = var.cp_disk_size
    file_format  = "raw"
  }

  cpu {
    cores   = var.cp_cpus
    sockets = 1
    numa    = true
    type    = "host"
    flags   = [] 
  }

  memory {
    dedicated = var.cp_memory
    floating  = var.cp_memory
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
      #ipv4 {
      #  address = "${var.ipv4_address_prefix}${count.index + var.cp_octet_start}/${var.ipv4_address_subnet}"
      #  gateway = var.ipv4_gateway
      #}
      ipv6 {
        address = "${var.ipv6_address_prefix}${count.index + var.cp_octet_start}/${var.ipv6_address_subnet}"
        gateway = var.ipv6_gateway
      }
    }

    dns {
      servers   = var.dns_server
      domain    = var.dns_domain
    }
    
    datastore_id        = var.datastore_id
    user_data_file_id = var.user_data_file_id
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

}

resource "proxmox_virtual_environment_vm" "worker" {
  count = var.wkr_quantity
  name  = "${var.name_prefix}-worker-${count.index + 1}"

  # Distribute VMs across nodes based on index
  node_name = count.index % 3 == 1 ? "pve02" : count.index % 3 == 2 ? "pve03" : "pve01"

  vm_id = "${var.vlan_id}${format("%04d", count.index + var.wkr_octet_start)}"

  description = "Managed by Terraform"
  tags          = ["debian", "k8s-worker", "${var.name_prefix}", "terraform"]

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    file_id      = var.file_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    cache        = "writeback"
    size         = var.wkr_disk_size
    file_format  = "raw"
  }

  cpu {
    cores   = var.wkr_cpus
    sockets = 1
    numa    = true
    type    = "host"
    flags   = [] 
  }

  memory {
    dedicated = var.wkr_memory
    floating  = var.wkr_memory
  }

  agent {
    enabled = true
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = var.vlan_id
  }

  # Dynamic hostpci configuration
  dynamic "hostpci" {
    for_each = (count.index + 1) == 4 ? {
      hostpci0 = "00:02.1"
      hostpci1 = "00:02.2"
    } : (count.index + 1) == 5 ? {
      hostpci0 = "00:02.3"
      hostpci1 = "00:02.4"
    } : {}

    content {
      device = hostpci.key
      id     = hostpci.value
      pcie   = false
      rombar = true
      xvga   = false
    }
  }
  
  
  initialization {
    ip_config {
      #ipv4 {
      #  address = "${var.ipv4_address_prefix}${count.index + var.wkr_octet_start}/${var.ipv4_address_subnet}"
      #  gateway = var.ipv4_gateway
      #}
      ipv6 {
        address = "${var.ipv6_address_prefix}${count.index + var.wkr_octet_start}/${var.ipv6_address_subnet}"
        gateway = var.ipv6_gateway
      }
    }

    dns {
      servers   = var.dns_server
      domain    = var.dns_domain
    }

    datastore_id      = var.datastore_id
    user_data_file_id = var.user_data_file_id
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

}
