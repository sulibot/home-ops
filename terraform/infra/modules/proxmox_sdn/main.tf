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

# OSPF underlay fabric (prototype) - replaces the hand-rolled FRR OSPF
# stanzas on the two mesh links (enp1s0f0np0/enp1s0f1np1) that today provide
# loopback reachability between PVE hosts for the EVPN BGP overlay.
# Deliberately scoped to just the mesh links: lo-svcs and vmbr0.10 stay OSPF
# via frr.conf.local since they serve Ceph advertisement and management
# reachability, not fabric underlay - not something PVE Fabrics models.
resource "proxmox_sdn_fabric_ospf" "underlay" {
  count = var.enable_underlay_fabric ? 1 : 0

  id       = "underlay"
  area     = var.fabric_ospf_area
  ip_prefix = var.fabric_ospf_prefix
}

resource "proxmox_sdn_fabric_node_ospf" "underlay" {
  for_each = var.enable_underlay_fabric ? var.fabric_nodes : {}

  fabric_id       = proxmox_sdn_fabric_ospf.underlay[0].id
  node_id         = each.key
  ip              = each.value.ip
  interface_names = each.value.interface_names
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
      proxmox_sdn_fabric_ospf.underlay,
      proxmox_sdn_fabric_node_ospf.underlay,
    ]
  }

  depends_on = [
    proxmox_sdn_fabric_ospf.underlay,
    proxmox_sdn_fabric_node_ospf.underlay,
  ]
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
