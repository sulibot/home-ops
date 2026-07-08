output "ha_resource_ids" {
  description = "Managed HA resource IDs."
  value       = keys(proxmox_haresource.this)
}

output "ha_rule_ids" {
  description = "Managed HA rule IDs."
  value       = keys(proxmox_harule.this)
}
