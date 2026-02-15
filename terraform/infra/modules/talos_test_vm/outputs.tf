output "vm_id" {
  value       = proxmox_virtual_environment_vm.talos.vm_id
  description = "Proxmox VM ID"
}

output "vm_name" {
  value       = var.vm_name
  description = "VM hostname"
}

output "ipv4_address" {
  value       = var.network.ipv4_address
  description = "VM IPv4 address"
}

output "ipv6_address" {
  value       = var.network.ipv6_address
  description = "VM IPv6 address"
}

output "bgp_asn" {
  value       = var.bgp_config.local_asn
  description = "BIRD2 BGP ASN"
}

output "talosconfig" {
  value       = data.talos_client_configuration.this.talos_config
  description = "Talos client configuration for talosctl"
  sensitive   = true
}

output "talosctl_command" {
  value       = "talosctl -n ${var.network.ipv4_address} --talosconfig <talosconfig-file>"
  description = "Talosctl command template to connect to VM"
}
