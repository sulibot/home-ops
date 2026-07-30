terraform {
  backend "gcs" {}

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.0"
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
    config_patches        = list(string)
  }))
  description = "Machine configurations for all nodes"
  sensitive   = true
}

variable "apply_mode" {
  type        = string
  description = "Talos machine configuration apply mode."
  default     = "staged_if_needing_reboot"
}

variable "on_destroy" {
  type = object({
    reset    = bool
    reboot   = bool
    graceful = bool
  })
  description = "Safety controls for talos_machine_configuration_apply destroy behavior."
  default = {
    reset    = false
    reboot   = false
    graceful = true
  }
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

      NODES=(${join(" ", [for name, ips in var.all_node_ips : ips.ipv6])})
      RETRIES=10  # 10 retries * 3 seconds = 30 seconds max per node

      for NODE in "$${NODES[@]}"; do
        ATTEMPT=0
        echo "Checking network connectivity to $NODE..."

        while [ $ATTEMPT -lt $RETRIES ]; do
          ATTEMPT=$((ATTEMPT + 1))

          # Simple network check - can we reach the node at all? (IPv6; macOS
          # ping doesn't accept IPv6 literals, needs ping6 - Linux's ping6
          # works too, so prefer it uniformly across platforms)
          if command -v ping6 >/dev/null 2>&1; then
            PING_OK=$(ping6 -c 1 "$NODE" >/dev/null 2>&1 && echo 1 || echo 0)
          else
            PING_OK=$(ping -6 -c 1 -W 2 "$NODE" >/dev/null 2>&1 && echo 1 || echo 0)
          fi
          if [ "$PING_OK" = "1" ]; then
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
  apply_mode                  = var.apply_mode

  config_patches = [for patch in var.machine_configs[each.key].config_patches : replace(patch, "$$", "$")]
  on_destroy     = var.on_destroy

  # Apply configs via IPv6. Was IPv4 (comment claimed the IPv6 ULA was
  # VRF-internal and unreachable from a workstation) - that's no longer true
  # (or never was for this workstation): IPv4 to these nodes now times out /
  # "no route to host" reliably here, while IPv6 has been reachable
  # throughout (talosctl against these same addresses works fine). See
  # docs/tickets/eng-322-vrf-evpnz1-ipv4-snat.md.
  endpoint = var.all_node_ips[each.key].ipv6

  # Wait for health check before applying
  depends_on = [null_resource.wait_for_nodes]
}

output "applied_nodes" {
  value       = keys(talos_machine_configuration_apply.nodes)
  description = "List of nodes that had configs applied"
}

output "requested_apply_mode" {
  value       = var.apply_mode
  description = "Requested Talos apply mode."
}

output "resolved_apply_modes" {
  value = {
    for name, res in talos_machine_configuration_apply.nodes :
    name => res.resolved_apply_mode
  }
  description = "Resolved apply mode per node as reported by Talos provider."
}
