terraform {
  backend "local" {}

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.9.0"
    }
  }
}

variable "region" {
  type        = string
  description = "Region (unused, for compatibility)"
  default     = "home-lab"
}

variable "cluster_id" {
  type        = number
  description = "Cluster ID"
}

variable "talosconfig" {
  type        = string
  description = "Talos configuration YAML for health checks"
  sensitive   = false
}

variable "client_configuration" {
  type = object({
    ca_certificate     = string
    client_certificate = string
    client_key         = string
  })
  description = "Talos client configuration"
  sensitive   = true
}

variable "machine_configs" {
  type = map(object({
    machine_configuration = string
    config_patch          = string
  }))
  description = "Machine configurations for all nodes"
  sensitive   = true
}

variable "all_node_names" {
  type        = list(string)
  description = "List of all node names"
}

variable "all_node_ips" {
  type = map(object({
    ipv6 = string
    ipv4 = string
  }))
  description = "IP addresses for all nodes"
}

# Health check: Wait for all nodes to be responsive before applying configs
resource "null_resource" "wait_for_nodes" {
  triggers = {
    # Re-run health check if node IPs change
    node_ips = jsonencode(var.all_node_ips)
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "🔍 Checking network connectivity to all Talos nodes before applying configs..."

      NODES=(${join(" ", [for name, ips in var.all_node_ips : ips.ipv4])})
      RETRIES=10  # 10 retries * 3 seconds = 30 seconds max per node

      for NODE in "$${NODES[@]}"; do
        ATTEMPT=0
        echo "Checking network connectivity to $NODE..."

        while [ $ATTEMPT -lt $RETRIES ]; do
          ATTEMPT=$((ATTEMPT + 1))

          # Simple network check - can we reach the node at all?
          if ping -c 1 -W 2 "$NODE" >/dev/null 2>&1; then
            echo "✓ Node $NODE is network reachable"
            break
          fi

          if [ $ATTEMPT -lt $RETRIES ]; then
            echo "   Node $NODE not reachable (attempt $ATTEMPT/$RETRIES), waiting 3 seconds..."
            sleep 3
          else
            echo "⚠ Node $NODE network check timed out after 30 seconds"
            echo "   Proceeding anyway - node may still be booting"
          fi
        done
      done

      echo "✓ Network check complete - proceeding with config apply"
    EOT

    environment = {
      TALOSCONFIG = var.talosconfig
    }
  }
}

# Apply machine configurations to all nodes
# This resource will update configs on running nodes without bootstrapping
resource "talos_machine_configuration_apply" "nodes" {
  for_each = toset(var.all_node_names)

  client_configuration        = var.client_configuration
  machine_configuration_input = replace(var.machine_configs[each.key].machine_configuration, "$$", "$")
  node                        = each.key

  config_patches = [
    replace(var.machine_configs[each.key].config_patch, "$$", "$")
  ]

  # Apply configs via IPv4 (IPv6 ULA is in VRF and not reachable from workstation)
  endpoint = var.all_node_ips[each.key].ipv4

  # Wait for health check before applying
  depends_on = [null_resource.wait_for_nodes]
}

output "applied_nodes" {
  value       = keys(talos_machine_configuration_apply.nodes)
  description = "List of nodes that had configs applied"
}
