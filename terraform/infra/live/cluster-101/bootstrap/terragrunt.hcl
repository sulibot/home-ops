include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "talos_config" {
  config_path = "../talos-config"

  mock_outputs = {
    talosconfig          = "mock"
    client_configuration = {}
    machine_configs      = {}
    control_plane_ips    = {}
    all_node_names       = []
    all_node_ips         = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../modules/talos_bootstrap"
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  secrets        = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/infra/live/common/secrets.sops.yaml"))
}

inputs = {
  cluster_id           = local.cluster_config.cluster_id
  talosconfig          = dependency.talos_config.outputs.talosconfig
  client_configuration = dependency.talos_config.outputs.client_configuration
  machine_configs      = dependency.talos_config.outputs.machine_configs
  control_plane_nodes  = dependency.talos_config.outputs.control_plane_ips
  all_node_names       = dependency.talos_config.outputs.all_node_names
  all_node_ips         = dependency.talos_config.outputs.all_node_ips

  # Flux GitOps configuration
  flux_git_repository  = "https://github.com/sulibot/home-ops.git"
  flux_git_branch      = "main"
  flux_github_token    = local.secrets.github_token

  # SOPS AGE key for decrypting secrets (read from file to keep it out of state)
  sops_age_key         = get_env("SOPS_AGE_KEY_FILE", "") != "" ? file(get_env("SOPS_AGE_KEY_FILE")) : ""
}
