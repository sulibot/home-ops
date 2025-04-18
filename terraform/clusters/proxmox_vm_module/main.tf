locals {
  base_vmid = replace(var.ipv4_address_prefix, ".", "")
  ssh_hosts = {
    pve01 = "fd00:255::1"
    pve02 = "fd00:255::2"
    pve03 = "fd00:255::3"
  }

  controlplane_nodes = {
    for i in range(1, var.cp_quantity + 1) :
    "cp${i}" => {
      index         = i - 1
      padded_suffix = format("%02d", i)
    }
  }

  worker_nodes = {
    for i in range(1, var.wkr_quantity + 1) :
    "wk${i}" => {
      index         = i - 1
      padded_suffix = format("%02d", i)
    }
  }
}

variable "vm_password_hashed" {
  description = "Hashed VM user password (already processed upstream)"
  type        = string
  sensitive   = true
}

resource "proxmox_virtual_environment_file" "worker_cloudinit" {
  for_each     = local.worker_nodes
  content_type = "snippets"
  datastore_id = var.datastore_id
  node_name    = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"

  source_raw {
    file_name = "worker-wk${each.value.padded_suffix}-cloud-init.yaml"
    data = templatefile("${path.module}/templates/user-data-cloud-config.tmpl", {
      hostname = "${var.name_prefix}wk${each.value.padded_suffix}"
    })
  }
}

resource "proxmox_virtual_environment_file" "controlplane_cloudinit" {
  for_each     = local.controlplane_nodes
  content_type = "snippets"
  datastore_id = var.datastore_id
  node_name    = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"

  source_raw {
    file_name = "controlplane-cp${each.value.padded_suffix}-cloud-init.yaml"
    data = templatefile("${path.module}/templates/user-data-cloud-config.tmpl", {
      hostname = "${var.name_prefix}cp${each.value.padded_suffix}"
    })
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each   = local.worker_nodes
  name       = "${var.name_prefix}wk${each.value.padded_suffix}"
  node_name  = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"
  vm_id      = "${var.vlan_id}${format("%04d", each.value.index + var.wkr_octet_start)}"

  description   = "Managed by Terraform"
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

  dynamic "hostpci" {
    for_each = (each.value.index + 1) == 4 ? {
      hostpci0 = "00:02.1"
      hostpci1 = "00:02.2"
    } : (each.value.index + 1) == 5 ? {
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
      ipv6 {
        address = "${var.ipv6_address_prefix}${each.value.index + var.wkr_octet_start}/${var.ipv6_address_subnet}"
        gateway = var.ipv6_gateway
      }
    }

    dns {
      servers = var.dns_server
      domain  = var.dns_domain
    }

    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.worker_cloudinit[each.key].id
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

resource "proxmox_virtual_environment_vm" "controlplane" {
  for_each   = local.controlplane_nodes
  name       = "${var.name_prefix}cp${each.value.padded_suffix}"
  node_name  = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"
  vm_id      = "${var.vlan_id}${format("%04d", each.value.index + var.cp_octet_start)}"

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
      ipv6 {
        address = "${var.ipv6_address_prefix}${each.value.index + var.cp_octet_start}/${var.ipv6_address_subnet}"
        gateway = var.ipv6_gateway
      }
    }

    dns {
      servers = var.dns_server
      domain  = var.dns_domain
    }

    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.controlplane_cloudinit[each.key].id
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