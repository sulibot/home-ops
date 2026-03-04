terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.97.0" }
    null    = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

locals {
  node_names = toset([for c in values(var.containers) : c.node_name])

  template_file_ids = var.template.download ? {
    for name, c in var.containers : name => proxmox_virtual_environment_download_file.lxc_template[c.node_name].id
    } : {
    for name, _ in var.containers : name => var.template.file_id
  }
}

resource "proxmox_virtual_environment_download_file" "lxc_template" {
  for_each = var.template.download ? local.node_names : []

  content_type = "vztmpl"
  datastore_id = var.proxmox.datastore_id
  node_name    = each.value
  url          = var.template.url
  file_name    = var.template.file_name

  lifecycle {
    ignore_changes = [url]
  }
}

resource "proxmox_virtual_environment_container" "this" {
  for_each = var.containers

  vm_id       = each.value.vm_id
  node_name   = each.value.node_name
  description = each.value.description
  tags        = each.value.tags

  started = each.value.started

  operating_system {
    template_file_id = local.template_file_ids[each.key]
    type             = "debian"
  }

  disk {
    datastore_id = var.proxmox.vm_datastore
    size         = each.value.disk_gb
  }

  dynamic "mount_point" {
    for_each = each.value.mount_points
    content {
      volume = mount_point.value.volume
      size   = mount_point.value.size
      path   = mount_point.value.path
    }
  }

  cpu {
    cores = each.value.cpu_cores
  }

  memory {
    dedicated = each.value.memory_mb
    swap      = each.value.swap_mb
  }

  network_interface {
    name     = "eth0"
    bridge   = each.value.bridge
    vlan_id  = try(each.value.vlan_id, null)
    firewall = each.value.firewall
  }

  features {
    nesting = try(each.value.features.nesting, false)
    keyctl  = try(each.value.features.keyctl, false)
  }

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = each.value.ipv4_gateway
      }
      ipv6 {
        address = each.value.ipv6_address
        gateway = each.value.ipv6_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      keys = each.value.ssh_public_keys
    }
  }

  lifecycle {
    ignore_changes = all
  }
}

resource "null_resource" "provision" {
  for_each = var.provision.enabled ? var.containers : {}

  depends_on = [proxmox_virtual_environment_container.this]

  triggers = {
    container_id = proxmox_virtual_environment_container.this[each.key].id
    commands_sha = sha256(join("\n", var.provision.commands))
  }

  connection {
    type        = "ssh"
    user        = var.provision.ssh_user
    private_key = var.provision.ssh_private_key
    host        = split("/", each.value.ipv4_address)[0]
    timeout     = var.provision.ssh_timeout
  }

  provisioner "remote-exec" {
    inline = concat(
      var.provision.wait_for_cloudinit ? ["cloud-init status --wait 2>/dev/null || true"] : [],
      var.provision.commands
    )
  }
}
