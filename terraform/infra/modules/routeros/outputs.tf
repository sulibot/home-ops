output "bgp_template" {
  description = "BGP template name"
  value       = routeros_routing_bgp_template.pve_fabric.name
}

output "bgp_connection" {
  description = "BGP connection name"
  value       = routeros_routing_bgp_connection.edge.name
}
