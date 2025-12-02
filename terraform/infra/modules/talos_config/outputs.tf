output "talosconfig" {
  description = "Talosconfig for CLI access"
  value       = data.talos_client_configuration.cluster.talos_config
  sensitive   = true
}

output "machine_configs" {
  description = "Generated machine configurations for all nodes"
  value = {
    for node_name, config in local.machine_configs : node_name => {
      machine_type          = config.machine_type
      machine_configuration = replace(config.machine_configuration, "$", "$$")
      config_patch          = replace(config.config_patch, "$", "$$")
    }
  }
  sensitive = true
}

output "cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = var.cluster_endpoint
}

output "control_plane_ips" {
  description = "Control plane node IP addresses"
  value = {
    for name, node in local.control_plane_nodes :
    name => {
      ipv6 = node.public_ipv6
      ipv4 = node.public_ipv4
    }
  }
}

output "all_node_ips" {
  description = "All node IP addresses (for bootstrap endpoint access)"
  value = {
    for name, node in local.all_nodes :
    name => {
      ipv6 = node.public_ipv6
      ipv4 = node.public_ipv4
    }
  }
}

output "machine_secrets" {
  description = "Talos machine secrets (for bootstrap module)"
  value       = talos_machine_secrets.cluster.machine_secrets
  sensitive   = true
}

output "all_node_names" {
  description = "List of all node names (non-sensitive for for_each)"
  value       = keys(var.all_node_ips)
  sensitive   = false
}

output "client_configuration" {
  description = "Talos client configuration object (for Terraform provider)"
  value       = talos_machine_secrets.cluster.client_configuration
  sensitive   = true
}

output "secrets_yaml" {
  description = "Talos secrets in YAML format (for adding new nodes)"
  value       = yamlencode(talos_machine_secrets.cluster.machine_secrets)
  sensitive   = true
}
