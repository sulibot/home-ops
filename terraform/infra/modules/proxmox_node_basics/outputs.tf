output "node_names" {
  description = "Managed node names."
  value       = keys(proxmox_node_config.this)
}
