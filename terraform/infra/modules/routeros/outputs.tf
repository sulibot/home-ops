output "bgp_template" {
  description = "BGP template name"
  value       = routeros_routing_bgp_template.pve_fabric.name
}

output "bgp_connection" {
  description = "BGP connection name"
  value       = routeros_routing_bgp_connection.edge.name
}

output "wireguard_public_keys" {
  description = "Public keys for each managed WireGuard interface, keyed by interface name."
  value       = { for name, iface in routeros_interface_wireguard.interfaces : name => iface.public_key }
}
