include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config    = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  output_directory  = "${get_repo_root()}/talos/clusters/${local.cluster_config.cluster_name}"
  cluster_enabled   = try(local.cluster_config.enabled, true)
  kubeconfig_path   = "${local.output_directory}/kubeconfig"
  kubeconfig_exists = fileexists(local.kubeconfig_path)
  kubernetes_api_ready = local.kubeconfig_exists && trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.kubeconfig_path}' timeout 8 kubectl get --raw=/readyz >/dev/null 2>&1 && echo true || echo false"
  )) == "true"
  forced_talos_apply_mode    = trimspace(get_env("TALOS_APPLY_MODE", ""))
  default_talos_apply_mode   = local.kubernetes_api_ready ? try(local.cluster_config.talos_apply_mode, "staged_if_needing_reboot") : "auto"
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
    all_node_names        = []
    all_node_ips          = {}
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
