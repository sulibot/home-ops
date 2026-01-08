# Apply Talos machine configurations to running nodes
# This step ONLY applies configs - it does NOT bootstrap the cluster
# Use this to update machine configs on an already-running cluster
#
# EXCLUDED from run-all to avoid conflict with bootstrap
# To run explicitly: terragrunt apply --terragrunt-working-dir ./apply

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Exclude this module from run-all operations (bootstrap already applies configs)
# Note: This prevents redundant config application since bootstrap includes apply
locals {
  # Always exclude this module - it should only be run manually for config updates
  should_exclude = true
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
}

exclude {
  if = local.should_exclude
  actions = ["all"]
  exclude_dependencies = false
}

dependency "talos_config" {
  config_path = "../config"

  mock_outputs = {
    talosconfig          = "mock"
    client_configuration = {
      ca_certificate     = "mock-ca"
      client_certificate = "mock-cert"
      client_key         = "mock-key"
    }
    machine_configs      = {}
    control_plane_ips    = {}
    all_node_names       = []
    all_node_ips         = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/talos_apply_config"
}

inputs = {
  cluster_id           = local.cluster_config.cluster_id
  talosconfig          = dependency.talos_config.outputs.talosconfig
  client_configuration = dependency.talos_config.outputs.client_configuration
  machine_configs      = dependency.talos_config.outputs.machine_configs
  all_node_names       = dependency.talos_config.outputs.all_node_names
  all_node_ips         = dependency.talos_config.outputs.all_node_ips
}
