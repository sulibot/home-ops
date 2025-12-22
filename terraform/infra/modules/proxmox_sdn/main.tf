# Proxmox SDN EVPN Module
# Creates EVPN zone, VNets, and subnets for software-defined networking

# EVPN Zone - uses FRR BGP on each PVE host
resource "proxmox_virtual_environment_sdn_zone_evpn" "main" {
  id         = var.zone_id
  controller = "frr" # FRR controller running on each PVE host
  vrf_vxlan  = var.vrf_vxlan
  mtu        = var.mtu
  nodes      = var.nodes

  # Exit nodes for internet/external access via SNAT
  # All PVE nodes act as exit nodes for redundancy
  exit_nodes               = var.exit_nodes
  exit_nodes_local_routing = true # Use local routing table on exit nodes
  primary_exit_node        = var.primary_exit_node

  # Import default route from RouterOS into VRF
  rt_import = var.rt_import
}

# VNets - one per cluster/workload type
resource "proxmox_virtual_environment_sdn_vnet" "vnets" {
  for_each = var.vnets

  id    = each.key
  zone  = proxmox_virtual_environment_sdn_zone_evpn.main.id
  alias = each.value.alias
  tag   = each.value.vxlan_id # VXLAN ID
}

# IPv4 Subnets (optional)
resource "proxmox_virtual_environment_sdn_subnet" "ipv4_subnets" {
  for_each = {
    for k, v in var.vnets : k => v
    if v.subnet_v4 != null
  }

  vnet    = proxmox_virtual_environment_sdn_vnet.vnets[each.key].id
  cidr    = each.value.subnet_v4
  gateway = each.value.gateway_v4
  snat    = false

  depends_on = [proxmox_virtual_environment_sdn_vnet.vnets]
}

# ULA Subnets - Stable internal IPv6 addressing
# These addresses persist even if ISP changes delegated prefix
resource "proxmox_virtual_environment_sdn_subnet" "ula_subnets" {
  for_each = var.vnets

  vnet    = proxmox_virtual_environment_sdn_vnet.vnets[each.key].id
  cidr    = each.value.subnet
  gateway = each.value.gateway
  snat    = false  # No SNAT - VMs use their real GUA addresses

  depends_on = [proxmox_virtual_environment_sdn_vnet.vnets]
}

# GUA Subnets - Internet-routable IPv6 using AT&T delegated prefixes
# VMs get both ULA (stable) and GUA (internet-routable) addresses via SLAAC
resource "proxmox_virtual_environment_sdn_subnet" "gua_subnets" {
  for_each = var.delegated_prefixes

  vnet    = proxmox_virtual_environment_sdn_vnet.vnets[each.key].id
  cidr    = each.value.prefix
  gateway = each.value.gateway
  snat    = false

  depends_on = [proxmox_virtual_environment_sdn_vnet.vnets]
}

# Applier - triggers SDN configuration application
resource "proxmox_virtual_environment_sdn_applier" "main" {
  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_zone_evpn.main,
      proxmox_virtual_environment_sdn_vnet.vnets,
      proxmox_virtual_environment_sdn_subnet.ipv4_subnets,
      proxmox_virtual_environment_sdn_subnet.ula_subnets,
      proxmox_virtual_environment_sdn_subnet.gua_subnets,
    ]
  }
}
