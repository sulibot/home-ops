terraform {
  backend "local" {}
}

variable "region" {
  type        = string
  description = "Region (unused, for compatibility with root.hcl)"
  default     = "home-lab"
}

variable "talosconfig_path" {
  type        = string
  description = "Path to talosconfig file"
}

variable "machine_configs" {
  type = map(object({
    config_patch = string
  }))
  description = "Per-node config patches"
  sensitive   = true
}

variable "all_node_ips" {
  type = map(object({
    ipv6 = string
    ipv4 = string
  }))
  description = "Node IP addresses"
}

# Minimal state tracking - actual patching is done by Terragrunt hooks
# This allows Terraform to track that patches have been applied
locals {
  node_names    = keys(var.all_node_ips)
  patches_hash  = sha256(jsonencode([for k in local.node_names : sha256(var.machine_configs[k].config_patch)]))
  last_applied  = timestamp()
}

# Terraform data source to track patch state
# The actual patch application is handled by Terragrunt after_hook
# When patches_hash changes, this resource will be replaced, triggering the hooks
resource "terraform_data" "patch_state" {
  input = {
    patches_hash = local.patches_hash
    node_count   = length(local.node_names)
    last_applied = local.last_applied
  }

  # Force replacement when input changes (triggers Terragrunt hooks)
  triggers_replace = {
    patches_hash = local.patches_hash
  }
}

output "patched_nodes" {
  value       = local.node_names
  description = "List of nodes configured for patching"
}

output "patches_hash" {
  value       = local.patches_hash
  description = "Hash of all patch configurations"
  sensitive   = true
}

output "patch_state" {
  value = {
    node_count   = terraform_data.patch_state.output.node_count
    last_applied = terraform_data.patch_state.output.last_applied
  }
  description = "Patch application state"
}
