output "account_names" {
  description = "Managed ACME account names."
  value       = keys(proxmox_acme_account.this)
}

output "dns_plugin_names" {
  description = "Managed ACME DNS plugin names."
  value       = keys(proxmox_acme_dns_plugin.this)
}
