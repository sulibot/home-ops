output "metrics_server_names" {
  description = "Managed Proxmox metrics server names."
  value       = keys(proxmox_metrics_server.this)
}
