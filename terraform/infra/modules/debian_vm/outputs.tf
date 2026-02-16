output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.debian.vm_id
}

output "vm_name" {
  description = "VM name"
  value       = proxmox_virtual_environment_vm.debian.name
}

output "ipv4_address" {
  description = "IPv4 address"
  value       = var.network.ipv4_address
}

output "ipv6_address" {
  description = "IPv6 address"
  value       = var.network.ipv6_address
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh root@${var.network.ipv4_address}"
}
