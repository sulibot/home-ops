output "zone_id" {
  description = "EVPN zone ID"
  value       = proxmox_virtual_environment_sdn_zone_evpn.main.id
}

output "vnet_ids" {
  description = "Map of VNet names to their IDs"
  value       = { for k, v in proxmox_virtual_environment_sdn_vnet.vnets : k => v.id }
}

output "ipv4_subnet_ids" {
  description = "Map of VNet names to their IPv4 subnet IDs"
  value       = { for k, v in proxmox_virtual_environment_sdn_subnet.ipv4_subnets : k => v.id }
}

output "ula_subnet_ids" {
  description = "Map of VNet names to their ULA subnet IDs"
  value       = { for k, v in proxmox_virtual_environment_sdn_subnet.ula_subnets : k => v.id }
}

output "gua_subnet_ids" {
  description = "Map of VNet names to their GUA subnet IDs"
  value       = { for k, v in proxmox_virtual_environment_sdn_subnet.gua_subnets : k => v.id }
}

output "vnet_gateways" {
  description = "Map of VNet names to their gateway addresses (IPv6)"
  value       = { for k, v in var.vnets : k => v.gateway }
}

output "vnet_gateways_v4" {
  description = "Map of VNet names to their IPv4 gateway addresses"
  value       = { for k, v in var.vnets : k => v.gateway_v4 if v.gateway_v4 != null }
}
