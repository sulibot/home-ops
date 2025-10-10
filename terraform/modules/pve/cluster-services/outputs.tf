output "acme_account" { value = proxmox_virtual_environment_acme_account.this.name }
output "dns_plugin" {
  value     = proxmox_virtual_environment_acme_dns_plugin.dns.plugin
  sensitive = true
}

