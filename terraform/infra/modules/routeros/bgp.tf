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
  name      = var.bgp.instance_name
  as        = tostring(var.bgp.local_asn)
  router_id = var.bgp.router_id
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
}
