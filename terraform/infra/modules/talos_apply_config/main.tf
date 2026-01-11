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

      echo "🔍 Checking health of all Talos nodes before applying configs..."

      NODES=(${join(" ", [for name, ips in var.all_node_ips : ips.ipv6])})
      RETRIES=30  # 30 retries * 10 seconds = 5 minutes max

      for NODE in "$${NODES[@]}"; do
        ATTEMPT=0
        echo "Checking node $NODE..."

        while [ $ATTEMPT -lt $RETRIES ]; do
          ATTEMPT=$((ATTEMPT + 1))

          if timeout 5 talosctl -n "$NODE" get addresses --insecure >/dev/null 2>&1; then
            echo "✓ Node $NODE is responsive"
            break
          fi

          if [ $ATTEMPT -lt $RETRIES ]; then
            echo "   Node $NODE not ready (attempt $ATTEMPT/$RETRIES), waiting 10 seconds..."
            sleep 10
          else
            echo "⚠ Node $NODE health check timed out after 5 minutes"
            echo "   Proceeding anyway - apply may fail if node is not ready"
          fi
        done
      done

      echo "✓ Health check complete - all responsive nodes ready for config apply"
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

  # Apply configs via IPv6 ULA (should work once we fix the addressing)
  # Falls back to IPv4 if IPv6 not available
  endpoint = var.all_node_ips[each.key].ipv6 != "" ? var.all_node_ips[each.key].ipv6 : var.all_node_ips[each.key].ipv4

  # Wait for health check before applying
  depends_on = [null_resource.wait_for_nodes]
}

output "applied_nodes" {
  value       = keys(talos_machine_configuration_apply.nodes)
  description = "List of nodes that had configs applied"
}
