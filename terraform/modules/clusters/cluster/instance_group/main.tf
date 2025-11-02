terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.83.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.86.3"
    }
  }
}

locals {
  proxmox_instances = ["pve01", "pve02", "pve03"]
  dns_domain        = "sulibot.com"

  # ---- Subnet layout (egress = vmbrX, mesh = meshX) ----
  egress_ipv4_iface_prefix  = "10.0.${var.cluster_id}"
  egress_ipv4_iface_gateway = "${local.egress_ipv4_iface_prefix}.254"
  egress_ipv6_iface_prefix  = "fd00:${var.cluster_id}"
  egress_ipv6_iface_gateway = "${local.egress_ipv6_iface_prefix}::fffe"

  mesh_ipv4_iface_prefix  = "10.10.${var.cluster_id}"
  mesh_ipv4_iface_gateway = "${local.mesh_ipv4_iface_prefix}.254"
  mesh_ipv6_iface_prefix  = "fc00:${var.cluster_id}"
  mesh_ipv6_iface_gateway = "${local.mesh_ipv6_iface_prefix}::fffe"

  # Per-node / "ID space" (loopbacks / host IDs)
  egress_ipv6_loopback_id_prefix = "fd00:255:${var.cluster_id}"
  egress_ipv4_loopback_id_prefix = "10.255.${var.cluster_id}"
  mesh_ipv6_loopback_id_prefix   = "fc00:255:${var.cluster_id}"
  mesh_ipv4_loopback_id_prefix   = "10.254.${var.cluster_id}"

  vip_ipv4_loopback_ip = "${local.egress_ipv4_loopback_id_prefix}.10"
  vip_ipv6_loopback_ip = "${local.egress_ipv6_loopback_id_prefix}::ac"

  # DNS servers (set to your infra; only include the stacks that are enabled)
  dns_server_ipv6 = "fd00:255::fffe"
  dns_server_ipv4 = "10.255.255.254"

  dns_servers = concat(
    var.enable_ipv6 ? [local.dns_server_ipv6] : [],
    var.enable_ipv4 ? [local.dns_server_ipv4] : []
  )

  egress_bridge = "vmbr0"
  mesh_bridge = "vnet${var.cluster_id}"

  hostname_prefix = format("%s%s", var.cluster_name, var.group.role_id)

  indices = [for i in range(var.group.instance_count) : tostring(i)]

  # Deterministic MACs, two NICs per VM (egress, mesh)
  mac_prefix = "02:00:00"
  mac_addresses = {
    for idx in local.indices : idx => {
      egress = format("%s:%02x:%02x:%02x", local.mac_prefix, var.cluster_id, var.group.segment_start + tonumber(idx), 1)
      mesh   = format("%s:%02x:%02x:%02x", local.mac_prefix, var.cluster_id, var.group.segment_start + tonumber(idx), 2)
    }
  }

  # Hostname ➜ mesh loopback ID records
  vm_hosts_ipv6 = {
    for idx in local.indices :
    "${format("%s%s%03d", var.cluster_name, var.group.role_id, var.group.segment_start + tonumber(idx))}.${local.dns_domain}" =>
    "${local.mesh_ipv6_loopback_id_prefix}::${var.group.segment_start + tonumber(idx)}"
  }

  vm_hosts_ipv4 = {
    for idx in local.indices :
    "${format("%s%s%03d", var.cluster_name, var.group.role_id, var.group.segment_start + tonumber(idx))}.${local.dns_domain}" =>
    "${local.mesh_ipv4_loopback_id_prefix}.${var.group.segment_start + tonumber(idx)}"
  }
}

# Validate that specified nodes exist
data "proxmox_virtual_environment_nodes" "available_nodes" {}

locals {
  available_node_names = data.proxmox_virtual_environment_nodes.available_nodes.names
  invalid_nodes = [
    for node in local.proxmox_instances : node
    if !contains(local.available_node_names, node)
  ]
}

resource "null_resource" "validate_nodes" {
  lifecycle {
    precondition {
      condition     = length(local.invalid_nodes) == 0
      error_message = "Invalid Proxmox nodes specified: ${join(", ", local.invalid_nodes)}"
    }
  }
}

# -------------------------------------------------------------------
# 1) Cloud-Init user-data (unchanged except for passing DNS/gateways)
# -------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "cloudinit" {
  for_each     = toset(local.indices)
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = local.proxmox_instances[tonumber(each.key) % length(local.proxmox_instances)]

  source_raw {
    file_name = format("%s%s%03d-user-data.yaml",
      var.cluster_name, var.group.role_id, var.group.segment_start + tonumber(each.key)
    )

    data = templatefile(var.cloudinit_template_file, {
      hostname                         = format("%s%03d", local.hostname_prefix, var.group.segment_start + tonumber(each.key))
      role                             = var.group.role
      cluster_name                     = var.cluster_name
      # Node IDs
      mesh_ipv6_loopback_id_ip         = "${local.mesh_ipv6_loopback_id_prefix}::${var.group.segment_start + tonumber(each.key)}"
      mesh_ipv4_loopback_id_ip         = "${local.mesh_ipv4_loopback_id_prefix}.${var.group.segment_start + tonumber(each.key)}"
      egress_ipv4_loopback_id_ip       = "${local.egress_ipv4_loopback_id_prefix}.${var.group.segment_start + tonumber(each.key)}"
      egress_ipv6_loopback_id_ip       = "${local.egress_ipv6_loopback_id_prefix}::${var.group.segment_start + tonumber(each.key)}"
      vip_ipv4_loopback_ip             = local.vip_ipv4_loopback_ip
      vip_ipv6_loopback_ip             = local.vip_ipv6_loopback_ip
      egress_ipv4_iface_gateway        = local.egress_ipv4_iface_gateway
      egress_ipv6_iface_gateway        = local.egress_ipv6_iface_gateway
      mesh_ipv4_iface_gateway          = local.mesh_ipv4_iface_gateway
      mesh_ipv6_iface_gateway          = local.mesh_ipv6_iface_gateway

      # Feature flags into cloud-init (if your template wants them)
      enable_ipv4                      = var.enable_ipv4
      enable_ipv6                      = var.enable_ipv6

      # FRR config
      frr_conf = templatefile(var.frr_template_file, {
        hostname                      = format("%s%03d", local.hostname_prefix, var.group.segment_start + tonumber(each.key))
        vip_ipv4_loopback_ip          = local.vip_ipv4_loopback_ip
        vip_ipv6_loopback_ip          = local.vip_ipv6_loopback_ip
        egress_ipv4_loopback_id_ip    = "${local.egress_ipv4_loopback_id_prefix}.${var.group.segment_start + tonumber(each.key)}"  # 10.255.<vlan>.<id>
        egress_ipv6_loopback_id_ip    = "${local.egress_ipv6_loopback_id_prefix}::${var.group.segment_start + tonumber(each.key)}"  # fd00:255:<vlan>::<id>
        router_id                     = "${local.egress_ipv4_loopback_id_prefix}.${var.group.segment_start + tonumber(each.key)}"  # use the v4 loopback ID as RID
        vm_asn                        = "65${var.cluster_id}"               # 65100/1/2/3...
        pve_asn                       = "65001"
        enable_ipv4                   = var.enable_ipv4
        enable_ipv6                   = var.enable_ipv6
        enable_mesh_ebgp              = true
        egress_ipv4_iface_ip          = "${local.egress_ipv4_iface_prefix}.${var.group.segment_start + tonumber(each.key)}"  # 10.0.<vlan>.<id>
        egress_ipv6_iface_ip          = "${local.egress_ipv6_iface_prefix}::${var.group.segment_start + tonumber(each.key)}" # fd00:<vlan>::<id>
        mesh_ipv4_iface_ip            = "${local.mesh_ipv4_iface_prefix}.${var.group.segment_start + tonumber(each.key)}"    # 10.10.<vlan>.<id>
        mesh_ipv6_iface_ip            = "${local.mesh_ipv6_iface_prefix}::${var.group.segment_start + tonumber(each.key)}"   # fc00:<vlan>::<id>
        mesh_ipv4_iface_gateway       = local.mesh_ipv4_iface_gateway
        mesh_ipv6_iface_gateway       = local.mesh_ipv6_iface_gateway
        egress_ipv6_iface_gateway     = local.egress_ipv6_iface_gateway
        egress_ipv4_iface_gateway     = local.egress_ipv4_iface_gateway
        ros_neighbor_v4               = "10.255.255.254"
        ros_neighbor_v6               = "fd00:255::fffe"
        ros_asn                       = "65000"
        bgp_port                      = "179"
        cluster_id                    = var.cluster_id
        segment_id                    = var.group.segment_start + tonumber(each.key)
        enable_bfd                    = "false"
      })
      daemons_conf = templatefile("${path.module}/templates/frr-daemons.tmpl", {
        enable_ipv4          = var.enable_ipv4
        enable_ipv6          = var.enable_ipv6
        egress_ipv4_loopback_id_ip = "${local.egress_ipv4_loopback_id_prefix}.${var.group.segment_start + tonumber(each.key)}"
        egress_ipv6_loopback_id_ip = "${local.egress_ipv6_loopback_id_prefix}::${var.group.segment_start + tonumber(each.key)}"
        egress_ipv4_iface_ip = "${local.egress_ipv4_iface_prefix}.${var.group.segment_start + tonumber(each.key)}"
        egress_ipv6_iface_ip = "${local.egress_ipv6_iface_prefix}::${var.group.segment_start + tonumber(each.key)}"
        bgp_port             = "179"
      })

      vip_health_bgp_sh = templatefile("${path.module}/templates/vip-health-bgp.sh.tmpl", {
        enable_ipv4          = var.enable_ipv4
        enable_ipv6          = var.enable_ipv6
        egress_ipv4_iface_ip = "${local.egress_ipv4_iface_prefix}.${var.group.segment_start + tonumber(each.key)}"  # 10.0.<vlan>.<id>
        egress_ipv6_iface_ip = "${local.egress_ipv6_iface_prefix}::${var.group.segment_start + tonumber(each.key)}" # fd00:<vlan>::<id>
        vip_ipv4_loopback_ip = local.vip_ipv4_loopback_ip
        vip_ipv6_loopback_ip = local.vip_ipv6_loopback_ip
      })

      vip_health_bgp_service = templatefile("${path.module}/templates/vip-health-bgp.service.tmpl", {
        enable_ipv4          = var.enable_ipv4
        enable_ipv6          = var.enable_ipv6
        vip_ipv6_loopback_ip = local.vip_ipv6_loopback_ip
        vip_ipv4_loopback_ip = local.vip_ipv4_loopback_ip
      })
    })
  }
}

# -------------------------------------------------------------------
# 2) VM definition + Cloud-Init IP configs (GUI-visible)
#     - IPv4/IPv6 blocks appear only if enabled
# -------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "instances" {
  for_each = toset(local.indices)

  name      = format("%s%s%03d",  var.cluster_name, var.group.role_id, var.group.segment_start + tonumber(each.key))
  node_name = local.proxmox_instances[tonumber(each.key) % length(local.proxmox_instances)]
  vm_id     = var.cluster_id * 1000 + (var.group.segment_start + tonumber(each.key))

  description = "Managed by Terraform"
  tags        = concat(["debian", var.cluster_name, var.group.role], [])
  protection  = false

  started         = true   # Start the VM
  stop_on_destroy = true

  clone {
    vm_id     = var.template_vmid
    node_name = local.proxmox_instances[0]
    full      = false      # Linked clone - faster
  }

  bios          = "ovmf"            # UEFI without Secure Boot
  machine       = "q35"
  on_boot       = true
  scsi_hardware = "virtio-scsi-pci"  # Faster than virtio-scsi-single

  # Explicitly disable agent waiting to prevent 15-minute timeouts
  # The qemu-guest-agent can still run in the VM for Proxmox integration,
  # but Terraform won't wait for it during provisioning/state refresh
  agent {
    enabled = false
  }

  # EFI disk (required for OVMF, but without Secure Boot keys)
  efi_disk {
    datastore_id      = var.datastore_id
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false        # No Secure Boot - faster boot
  }

  cpu {
    type    = "host"
    sockets = 1
    cores   = var.group.cpu_count
    # Performance flags
    flags   = ["+aes"]  # Enable AES-NI for faster crypto
  }

  memory {
    dedicated = var.group.memory_mb
    floating  = var.group.memory_mb
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.datastore_id
    file_format  = "raw"
    size         = var.group.disk_size_gb
    # Performance optimizations for Ceph RBD
    discard      = "on"           # Enable TRIM for better performance
    iothread     = true           # Dedicated I/O thread per disk
    ssd          = true           # Optimize for SSD
    cache        = "writeback"    # Best performance with RBD (Ceph handles durability)
  }

  # nic0: egress (vmbrX) — default gateway lives here
  network_device {
    bridge      = local.egress_bridge
    mtu         = 1
    mac_address = local.mac_addresses[each.key].egress
    vlan_id     = var.cluster_id
  }

  # nic1: mesh (meshX) — no default gateway
  network_device {
    bridge      = local.mesh_bridge
    mtu         = 1
    mac_address = local.mac_addresses[each.key].mesh
#    vlan_id     = "20${var.cluster_id}"
  }

  initialization {
    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.cloudinit[each.key].id

    dns {
      domain  = local.dns_domain
      # Only include servers for enabled stacks
      servers = local.dns_servers
    }

    # ---- IP CONFIG for NIC0 (Egress) ----
    ip_config {
      dynamic "ipv4" {
        for_each = var.enable_ipv4 ? [1] : []
        content {
          address = "${local.egress_ipv4_iface_prefix}.${var.group.segment_start + tonumber(each.key)}/24"
          gateway = local.egress_ipv4_iface_gateway  # uncomment if you want Proxmox to set it
        }
      }
      dynamic "ipv6" {
        for_each = var.enable_ipv6 ? [1] : []
        content {
          address = "${local.egress_ipv6_iface_prefix}::${var.group.segment_start + tonumber(each.key)}/64"
          # gateway = local.egress_ipv6_iface_gateway  # uncomment if you want Proxmox to set it
          # OR: address = "auto" / "dhcp" (pick one style across your fleet)
        }
      }
    }

    # ---- IP CONFIG for NIC1 (Mesh) ----
    ip_config {
      dynamic "ipv4" {
        for_each = var.enable_ipv4 ? [1] : []
        content {
          address = "${local.mesh_ipv4_iface_prefix}.${var.group.segment_start + tonumber(each.key)}/24"
        }
      }
      dynamic "ipv6" {
        for_each = var.enable_ipv6 ? [1] : []
        content {
          address = "${local.mesh_ipv6_iface_prefix}::${var.group.segment_start + tonumber(each.key)}/64"
        }
      }
    }
  }

  # Guard against both stacks being disabled
  lifecycle {
    precondition {
      condition     = var.enable_ipv4 || var.enable_ipv6
      error_message = "At least one of enable_ipv4 or enable_ipv6 must be true."
    }
  }

  depends_on = [null_resource.validate_nodes]

  # (Optional) Ignore GUI edits to IPs/DNS to prevent drift:
  # lifecycle {
  #   ignore_changes = [ initialization ]
  # }
}

# -------------------------------------------------------------------
# 3) RouterOS DNS records — conditional by stack
# -------------------------------------------------------------------

## AAAA (IPv6) only when IPv6 is enabled
#resource "routeros_ip_dns_record" "ipv6_records" {
#  for_each = var.enable_ipv6 ? local.vm_hosts_ipv6 : {}
#
#  name     = each.key
#  address  = each.value
#  type     = "AAAA"
#  ttl      = "300"
#  disabled = false
#}

## A (IPv4) only when IPv4 is enabled
#resource "routeros_ip_dns_record" "ipv4_records" {
#  for_each = var.enable_ipv4 ? local.vm_hosts_ipv4 : {}
#
#  name     = each.key
#  address  = each.value
#  type     = "A"
#  ttl      = "300"
#  disabled = false
#}
