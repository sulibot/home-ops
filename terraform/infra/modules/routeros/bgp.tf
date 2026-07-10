# BGP template and connection for PVE fabric peering
#
# Naming alignment with FRR templates:
#   ROS template PVE_FABRIC  <-> FRR router bgp 4200001000
#   ROS conn EDGE            <-> FRR peer-group EDGE4 / EDGE6
#   ROS local AS 4200000000  <-> FRR: EDGE_AS
#   ROS remote AS 4200001000 <-> FRR: LOCAL_AS / PVE_AS
#
# Single dual-stack connection (address_families=ip,ipv6) listening on the PVE
# infra loopback range. BFD enabled for fast failover.
#
# Provider v1.86.3 note: ROS7 replaced /routing/bgp/instance with
# /routing/bgp/template — use routeros_routing_bgp_template accordingly.

resource "routeros_routing_bgp_template" "pve_fabric" {
  name         = var.bgp.instance_name
  as           = tostring(var.bgp.local_asn)
  add_path_out = "none"
  # router_id not supported on ROS 7.20.1 — omit; uses global router-id

  lifecycle {
    ignore_changes = [add_path_out]
  }
}

resource "routeros_routing_bgp_connection" "edge" {
  name      = var.bgp.connection_name
  as        = tostring(var.bgp.local_asn)
  templates = [routeros_routing_bgp_template.pve_fabric.name]

  address_families = var.bgp.afi
  connect          = false
  listen           = true
  multihop         = true
  use_bfd          = var.bgp.use_bfd
  hold_time        = var.bgp.hold_time
  keepalive_time   = var.bgp.keepalive_time
  add_path_out     = "none"

  remote {
    address = var.bgp.remote_range
    as      = tostring(var.bgp.pve_asn)
  }

  local {
    address = var.bgp.local_address
    role    = "ebgp"
  }

  output {
    redistribute      = var.bgp.redistribute
    default_originate = var.bgp.default_originate
  }

  lifecycle {
    ignore_changes = [add_path_out]
  }
}

resource "routeros_routing_bgp_connection" "additional" {
  for_each = { for connection in var.additional_bgp_connections : connection.name => connection }

  name      = each.value.name
  as        = tostring(each.value.local_asn)
  templates = [routeros_routing_bgp_template.pve_fabric.name]

  address_families = each.value.afi
  connect          = each.value.connect
  listen           = each.value.listen
  multihop         = each.value.multihop
  use_bfd          = each.value.use_bfd
  hold_time        = each.value.hold_time
  keepalive_time   = each.value.keepalive_time

  remote {
    address = each.value.remote_address
    as      = tostring(each.value.remote_asn)
    port    = each.value.remote_port
  }

  local {
    address = each.value.local_address
    port    = each.value.local_port
    role    = each.value.local_role
  }

  output {
    redistribute      = each.value.redistribute
    default_originate = each.value.default_originate
  }

  lifecycle {
    ignore_changes = [add_path_out]
  }
}
