locals {
  _zone_nodes = [for n in var.nodes : n.name]  # pve01, pve02, ...
}

resource "proxmox_virtual_environment_sdn_zone_evpn" "zone" {
  for_each = var.configure_zones ? var.sdn_evpn_clusters : {}

  id                = "fab${each.key}"
  controller        = var.sdn_controller.id
  vrf_vxlan         = each.value.vrf_vxlan
  mtu               = each.value.mtu
  nodes             = local._zone_nodes
  advertise_subnets = true

  # Work around provider read-back flapping
  lifecycle {
    ignore_changes = [ipam, advertise_subnets, controller, vrf_vxlan, mtu]
  }

  depends_on = [
    null_resource.evpn_controller,   # controller must exist first
    # no fabric dependency in peer model
  ]
}
