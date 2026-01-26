output "vm_id" {
  value       = proxmox_virtual_environment_vm.debian.vm_id
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

output "frr_asn" {
  value       = var.frr_config != null ? var.frr_config.local_asn : null
  description = "FRR BGP ASN"
}

output "ssh_command" {
  value       = "ssh debian@${var.network.ipv4_address}"
  description = "SSH command to connect to VM"
}
