output "machine_secrets" {
  description = "Talos machine secrets (CA, tokens, etc.)"
  value       = talos_machine_secrets.cluster.machine_secrets
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration derived from machine secrets"
  value       = talos_machine_secrets.cluster.client_configuration
  sensitive   = true
}

output "secrets_yaml" {
  description = "Talos secrets in YAML format (for adding new nodes)"
  value       = yamlencode(talos_machine_secrets.cluster.machine_secrets)
  sensitive   = true
}
