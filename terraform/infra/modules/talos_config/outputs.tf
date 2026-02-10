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
  value       = local.machine_secrets
  sensitive   = true
}

output "all_node_names" {
  description = "List of all node names (non-sensitive for for_each)"
  value       = keys(var.all_node_ips)
  sensitive   = false
}

output "client_configuration" {
  description = "Talos client configuration object (for Terraform provider)"
  value       = local.client_configuration
  sensitive   = true
}

output "secrets_yaml" {
  description = "Talos secrets in YAML format (for adding new nodes)"
  value       = yamlencode(local.machine_secrets)
  sensitive   = true
}

# BGP Configuration Preview (for debugging)
output "bgp_config_preview" {
  description = "Preview of rendered bird2 config (first 800 chars per node, for debugging)"
  value = {
    for node_name in keys(local.bird2_config_confs) :
    node_name => substr(local.bird2_config_confs[node_name], 0, 800)
  }
  sensitive = false
}

output "bgp_asn_assignments" {
  description = "BGP ASN assignments per node (per-node ASN + node router-id)"
  value = {
    for node_name, node in local.all_nodes :
    node_name => {
      local_asn  = node.frr_asn  # Per-node ASN (e.g., 4210101011)
      remote_asn = var.bgp_remote_asn
      router_id  = "10.${var.cluster_id}.254.${node.node_suffix}"
    }
  }
  sensitive = false
}

output "cilium_bgp_node_configs_yaml" {
  description = "Generated CiliumBGPNodeConfig resources for per-node loopback peering"
  value       = local.cilium_bgp_node_configs_yaml
  sensitive   = false
}
