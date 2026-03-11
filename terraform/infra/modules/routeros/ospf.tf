resource "routeros_routing_ospf_instance" "instances" {
  for_each = { for i in var.ospf_instances : i.name => i }

  name              = each.value.name
  version           = each.value.version
  vrf               = each.value.vrf
  router_id         = each.value.router_id
  redistribute      = each.value.redistribute
  comment           = each.value.comment
  disabled          = each.value.disabled
  domain_id         = each.value.domain_id
  domain_tag        = each.value.domain_tag
  in_filter_chain   = each.value.in_filter_chain
  mpls_te_address   = each.value.mpls_te_address
  mpls_te_area      = each.value.mpls_te_area
  originate_default = each.value.originate_default
  out_filter_chain  = each.value.out_filter_chain
  out_filter_select = each.value.out_filter_select
  routing_table     = each.value.routing_table
}

resource "routeros_routing_ospf_area" "areas" {
  for_each = { for a in var.ospf_areas : a.name => a }

  name           = each.value.name
  instance       = each.value.instance
  area_id        = each.value.area_id
  type           = each.value.type
  comment        = each.value.comment
  default_cost   = each.value.default_cost
  disabled       = each.value.disabled
  no_summaries   = each.value.no_summaries
  nssa_translate = each.value.nssa_translate
}

resource "routeros_routing_ospf_interface_template" "templates" {
  for_each = {
    for t in var.ospf_interface_templates :
    "${t.area}-${join(",", tolist(t.interfaces))}-${join(",", tolist(t.networks))}" => t
  }

  area                = each.value.area
  interfaces          = each.value.interfaces
  networks            = each.value.networks
  instance_id         = each.value.instance_id
  type                = each.value.type
  cost                = each.value.cost
  hello_interval      = each.value.hello_interval
  dead_interval       = each.value.dead_interval
  retransmit_interval = each.value.retransmit_interval
  transmit_delay      = each.value.transmit_delay
  priority            = each.value.priority
  passive             = each.value.passive
  use_bfd             = each.value.use_bfd
  auth                = each.value.auth
  auth_id             = each.value.auth_id
  auth_key            = each.value.auth_key
  authentication_key  = each.value.authentication_key
  comment             = each.value.comment
  disabled            = each.value.disabled
  prefix_list         = each.value.prefix_list
  vlink_neighbor_id   = each.value.vlink_neighbor_id
  vlink_transit_area  = each.value.vlink_transit_area
}
