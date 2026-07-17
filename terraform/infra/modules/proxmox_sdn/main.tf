# Proxmox SDN EVPN Module
# Creates EVPN zone, VNets, and subnets for software-defined networking

# EVPN Zone - uses FRR BGP on each PVE host
resource "proxmox_sdn_zone_evpn" "main" {
  id                         = var.zone_id
  controller                 = "frr" # FRR controller running on each PVE host
  vrf_vxlan                  = var.vrf_vxlan
  mtu                        = var.mtu
  nodes                      = var.nodes
  advertise_subnets          = var.advertise_subnets
  disable_arp_nd_suppression = var.disable_arp_nd_suppression

  # Exit nodes for internet/external access via SNAT
  # All PVE nodes act as exit nodes for redundancy
  exit_nodes = var.exit_nodes
  # Required for PVE hosts and EVPN guests to exchange TCP with each other
  # (adds the xvrf veth pair between the default and evpn VRFs). With this
  # off, a guest could not reach services on its own node (e.g. tail01 ->
  # pve01:8006), which broke remote terraform runs entering via tailscale.
  exit_nodes_local_routing = true
  primary_exit_node        = var.primary_exit_node

  # Import default route from RouterOS into VRF
  rt_import = var.rt_import

  lifecycle {
    ignore_changes = [
      # Workaround for provider bug where these attributes are incorrectly reported as changed
      controller,
      vrf_vxlan,
      rt_import,
      # Provider returns inconsistent values for these fields on update.
      exit_nodes,
      primary_exit_node,
    ]
  }
}

# VNets - one per cluster/workload type
resource "proxmox_sdn_vnet" "vnets" {
  for_each = var.vnets

  id    = each.key
  zone  = proxmox_sdn_zone_evpn.main.id
  alias = each.value.alias
  tag   = each.value.vxlan_id # VXLAN ID
}

# IPv4 Subnets (optional)
resource "proxmox_sdn_subnet" "ipv4_subnets" {
  for_each = {
    for k, v in var.vnets : k => v
    if v.subnet_v4 != null
  }

  vnet    = proxmox_sdn_vnet.vnets[each.key].id
  cidr    = each.value.subnet_v4
  gateway = each.value.gateway_v4
  snat    = false

  depends_on = [proxmox_sdn_vnet.vnets]
}

# ULA Subnets - Stable internal IPv6 addressing
# These addresses persist even if ISP changes delegated prefix
resource "proxmox_sdn_subnet" "ula_subnets" {
  for_each = var.vnets

  vnet    = proxmox_sdn_vnet.vnets[each.key].id
  cidr    = each.value.subnet
  gateway = each.value.gateway
  snat    = false # No SNAT - VMs use their real GUA addresses

  depends_on = [proxmox_sdn_vnet.vnets]
}

# GUA Subnets - Internet-routable IPv6 using AT&T delegated prefixes
# VMs get both ULA (stable) and GUA (internet-routable) addresses via SLAAC
resource "proxmox_sdn_subnet" "gua_subnets" {
  for_each = var.delegated_prefixes

  vnet    = proxmox_sdn_vnet.vnets[each.key].id
  cidr    = each.value.prefix
  gateway = each.value.gateway
  snat    = false

  depends_on = [proxmox_sdn_vnet.vnets]
}

# Applier - triggers SDN configuration application
resource "proxmox_sdn_applier" "main" {
  count = var.apply_sdn_config ? 1 : 0

  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_zone_evpn.main,
      proxmox_sdn_vnet.vnets,
      proxmox_sdn_subnet.ipv4_subnets,
      proxmox_sdn_subnet.ula_subnets,
      proxmox_sdn_subnet.gua_subnets,
    ]
  }
}

# Reminder - notify user to run Ansible after SDN changes
resource "null_resource" "ansible_reminder_trigger" {
  count = var.apply_sdn_config ? 1 : 0

  depends_on = [proxmox_sdn_applier.main]

  triggers = {
    # Re-run this provisioner whenever the SDN applier resource is replaced.
    sdn_applier_id = proxmox_sdn_applier.main[0].id
  }

  provisioner "local-exec" {
    command = <<EOT
      echo "--------------------------------------------------------------------------------"
      echo "✅ Proxmox SDN configuration updated."
      echo ""
      echo "ACTION REQUIRED: Apply FRR configuration with Ansible."
      echo ""
      echo "Run the following commands from your terminal:"
      echo ""
      echo "cd $(git rev-parse --show-toplevel)/ansible/pve && ansible-playbook playbooks/21-frr.yml"
      echo ""
      echo "--------------------------------------------------------------------------------"
    EOT
  }
}
