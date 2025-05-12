

locals {

  cluster = var.cluster

  #cluster = module.common.clusters[var.cluster_key]


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
  datastore_id = local.cluster.datastore_id
  node_name    = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"

  source_raw {
    file_name = "worker-wk${each.value.padded_suffix}-cloud-init.yaml"
    data = templatefile("${path.module}/templates/user-data-cloud-config.tmpl", {
      hostname = "${var.cluster_name}wk${each.value.padded_suffix}"
      loopback_ipv6    = "${var.cluster.loopback_ipv6_prefix}::${each.value.index + var.wkr_octet_start}"
      mesh_gateway   = "${local.cluster.ipv6_mesh_gateway}"
    })
  }
}

resource "proxmox_virtual_environment_file" "controlplane_cloudinit" {
  for_each     = local.controlplane_nodes
  content_type = "snippets"
  datastore_id = local.cluster.datastore_id
  node_name    = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"

  source_raw {
    file_name = "controlplane-cp${each.value.padded_suffix}-cloud-init.yaml"
    data = templatefile("${path.module}/templates/user-data-cloud-config.tmpl", {
      hostname = "${var.cluster_name}cp${each.value.padded_suffix}"
      loopback_ipv6    = "${var.cluster.loopback_ipv6_prefix}::${each.value.index + var.cp_octet_start}"
      mesh_gateway   = "${local.cluster.ipv6_mesh_gateway}"
    })
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each   = local.worker_nodes
  name       = "${var.cluster_name}wk${each.value.padded_suffix}"
  node_name  = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"
  vm_id      = "${local.cluster.mesh_vlan_id}${format("%04d", each.value.index + var.wkr_octet_start)}"

  description   = "Managed by Terraform"
  tags          = ["debian", "k8s-worker", "${var.cluster_name}", "terraform"]
  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = local.cluster.datastore_id
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
    vlan_id = local.cluster.mesh_vlan_id
    mtu     = local.cluster.mesh_mtu
  }
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = local.cluster.egress_vlan_id
    mtu     = local.cluster.egress_mtu
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
        address = "${local.cluster.ipv6_mesh_prefix}::${each.value.index + var.wkr_octet_start}/${local.cluster.ipv6_address_subnet}"
        #  gateway = local.cluster.ipv6_mesh_gateway
      }
    }

    ip_config {
      ipv6 {
        address = "${local.cluster.ipv6_egress_prefix}::${each.value.index + var.wkr_octet_start}/${local.cluster.ipv6_address_subnet}"
        gateway = local.cluster.ipv6_egress_gateway
      }
    }

    dns {
      servers = local.cluster.ipv6_dns_server
      domain  = local.cluster.dns_domain
    }

    datastore_id      = local.cluster.datastore_id
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
  name       = "${var.cluster_name}cp${each.value.padded_suffix}"
  node_name  = each.value.index % 3 == 1 ? "pve02" : each.value.index % 3 == 2 ? "pve03" : "pve01"
  vm_id      = "${local.cluster.mesh_vlan_id}${format("%04d", each.value.index + var.cp_octet_start)}"

  description   = "Managed by Terraform"
  tags          = ["debian", "k8s-control-plane", "${var.cluster_name}", "terraform"]
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
    vlan_id = local.cluster.mesh_vlan_id
    mtu     = local.cluster.mesh_mtu
  }
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = local.cluster.egress_vlan_id
    mtu     = local.cluster.egress_mtu
  }

  initialization {
    ip_config {
      ipv6 {
        address = "${local.cluster.ipv6_mesh_prefix}::${each.value.index + var.cp_octet_start}/${local.cluster.ipv6_address_subnet}"
        #  gateway = local.cluster.ipv6_mesh_gateway
      }
    }

    ip_config {
      ipv6 {
        address = "${local.cluster.ipv6_egress_prefix}::${each.value.index + var.cp_octet_start}/${local.cluster.ipv6_address_subnet}"
        gateway = local.cluster.ipv6_egress_gateway
      }
    }

    dns {
      servers = local.cluster.ipv6_dns_server
      domain  = local.cluster.dns_domain
    }

    datastore_id      = local.cluster.datastore_id
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