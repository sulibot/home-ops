output "role_id" {
  description = "Managed Proxmox role ID."
  value       = proxmox_virtual_environment_role.this.role_id
}

output "user_id" {
  description = "Managed Proxmox user ID."
  value       = proxmox_virtual_environment_user.this.user_id
}

output "token_id" {
  description = "Managed Proxmox API token ID."
  value       = proxmox_user_token.provider.id
}

output "acl_id" {
  description = "Managed Proxmox ACL ID."
  value       = proxmox_acl.root.id
}
