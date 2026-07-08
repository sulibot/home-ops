output "openid_realm_ids" {
  description = "Managed OpenID realm IDs."
  value       = keys(proxmox_realm_openid.openid)
}
