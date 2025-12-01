# outputs.tf
output "vm_details" {
  description = "Details of created VMs"
  value = {
    for k, vm in proxmox_virtual_environment_vm.instances : k => {
      name        = vm.name
      node        = vm.node_name
      vm_id       = vm.vm_id
      ipv4_egress = var.enable_ipv4 ? "${local.egress_ipv4_iface_prefix}.${var.group.segment_start + tonumber(k)}" : null
      ipv6_egress = var.enable_ipv6 ? "${local.egress_ipv6_iface_prefix}::${var.group.segment_start + tonumber(k)}" : null
      ipv4_mesh   = var.enable_ipv4 ? "${local.mesh_ipv4_iface_prefix}.${var.group.segment_start + tonumber(k)}" : null
      ipv6_mesh   = var.enable_ipv6 ? "${local.mesh_ipv6_iface_prefix}::${var.group.segment_start + tonumber(k)}" : null
      ipv4_loopback = var.enable_ipv4 ? "${local.egress_ipv4_loopback_id_prefix}.${var.group.segment_start + tonumber(k)}" : null
      ipv6_loopback = var.enable_ipv6 ? "${local.egress_ipv6_loopback_id_prefix}::${var.group.segment_start + tonumber(k)}" : null
    }
  }
}

output "vip_addresses" {
  description = "VIP addresses for this cluster"
  value = {
    ipv4 = var.enable_ipv4 ? local.vip_ipv4_loopback_ip : null
    ipv6 = var.enable_ipv6 ? local.vip_ipv6_loopback_ip : null
  }
}

output "dns_records" {
  description = "DNS records that should be created"
  value = merge(
    var.enable_ipv4 ? local.vm_hosts_ipv4 : {},
    var.enable_ipv6 ? local.vm_hosts_ipv6 : {}
  )
}

output "cluster_info" {
  description = "Cluster networking information"
  value = {
    cluster_id   = var.cluster_id
    cluster_name = var.cluster_name
    role         = var.group.role
    vm_count     = var.group.instance_count
    egress_network = {
      ipv4_prefix  = var.enable_ipv4 ? "${local.egress_ipv4_iface_prefix}.0/24" : null
      ipv6_prefix  = var.enable_ipv6 ? "${local.egress_ipv6_iface_prefix}::/64" : null
      ipv4_gateway = var.enable_ipv4 ? local.egress_ipv4_iface_gateway : null
      ipv6_gateway = var.enable_ipv6 ? local.egress_ipv6_iface_gateway : null
    }
    mesh_network = {
      ipv4_prefix  = var.enable_ipv4 ? "${local.mesh_ipv4_iface_prefix}.0/24" : null
      ipv6_prefix  = var.enable_ipv6 ? "${local.mesh_ipv6_iface_prefix}::/64" : null
      ipv4_gateway = var.enable_ipv4 ? local.mesh_ipv4_iface_gateway : null
      ipv6_gateway = var.enable_ipv6 ? local.mesh_ipv6_iface_gateway : null
    }
  }
}