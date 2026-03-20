# Apply Talos machine configurations to running nodes
# This step ONLY applies configs - it does NOT bootstrap the cluster
# Safe to run repeatedly (used by run-all)

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id
  context        = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals

  cluster_enabled   = try(local.cluster_config.enabled, true)
  kubeconfig_path   = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/kubeconfig"
  kubeconfig_exists = fileexists(local.kubeconfig_path)
  kubernetes_api_ready = local.kubeconfig_exists && trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.kubeconfig_path}' timeout 8 kubectl get --raw=/readyz >/dev/null 2>&1 && echo true || echo false"
  )) == "true"
  bootstrap_complete         = local.kubernetes_api_ready
  forced_talos_apply_mode    = trimspace(get_env("TALOS_APPLY_MODE", ""))
  requested_talos_apply_mode = try(local.cluster_config.talos_apply_mode, local.context.talos_apply_mode_default)
  default_talos_apply_mode   = local.bootstrap_complete ? local.requested_talos_apply_mode : "auto"
  effective_talos_apply_mode = local.forced_talos_apply_mode != "" ? local.forced_talos_apply_mode : local.default_talos_apply_mode
}

skip = !local.cluster_enabled

dependency "talos_config" {
  config_path = "../config"

  mock_outputs = {
    talosconfig = "mock"
    client_configuration = {
      ca_certificate     = "mock-ca"
      client_certificate = "mock-cert"
      client_key         = "mock-key"
    }
    machine_apply_configs = {}
    control_plane_ips     = {}
    all_node_names        = []
    all_node_ips          = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/talos_apply_config"
}

inputs = {
  cluster_id           = local.tenant_id
  talosconfig          = dependency.talos_config.outputs.talosconfig
  client_configuration = dependency.talos_config.outputs.client_configuration
  machine_configs      = dependency.talos_config.outputs.machine_apply_configs
  all_node_names       = dependency.talos_config.outputs.all_node_names
  all_node_ips         = dependency.talos_config.outputs.all_node_ips
  apply_mode           = local.effective_talos_apply_mode

  on_destroy = {
    reset    = false
    reboot   = false
    graceful = true
  }
}
