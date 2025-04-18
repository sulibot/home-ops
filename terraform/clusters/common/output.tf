output "local_datastore" {
  value = local.datastore
}

output "local_dns_server" {
  value = local.dns_server
}

output "local_dns_domain" {
  value = local.dns_domain
}

output "local_vlan_common" {
  value = local.vlan_common
}

output "local_ip_config" {
  value = local.ip_config
}
output "vm_password_hashed" {
  value     = local.vm_password_hashed
  sensitive = true
}

output "pve_endpoint" {
  value     = local.pve_endpoint
  sensitive = true
}

output "pve_api_token_id" {
  value     = local.pve_api_token_id
  sensitive = true
}

output "pve_api_token_secret" {
  value     = local.pve_api_token_secret
  sensitive = true
}
