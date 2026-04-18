include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config   = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  output_directory = "${get_repo_root()}/talos/clusters/${local.cluster_config.cluster_name}"

  cluster_enabled    = try(local.cluster_config.enabled, true)
  bootstrap_mode     = trimspace(lower(get_env("TALOS_BOOTSTRAP_MODE", "false"))) == "true"
  cluster_kubeconfig = "${local.output_directory}/kubeconfig"
  kubernetes_api_ready = fileexists(local.cluster_kubeconfig) && trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.cluster_kubeconfig}' timeout 8 kubectl get --raw=/readyz >/dev/null 2>&1 && echo true || echo false"
  )) == "true"
}

skip = !local.cluster_enabled || (!local.bootstrap_mode && local.kubernetes_api_ready)

dependencies {
  paths = ["../apply"]
}

dependency "talos_config" {
  config_path = "../config"

  mock_outputs = {
    talosconfig = "mock"
    client_configuration = {
      ca_certificate     = "mock-ca"
      client_certificate = "mock-cert"
      client_key         = "mock-key"
    }
    cluster_endpoint  = "https://10.10.0.4:6443"
    control_plane_ips = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/talos_bootstrap"

  before_hook "prepare_output_directory" {
    commands = ["init", "validate", "plan", "apply", "destroy", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "mkdir -p '${local.output_directory}'"
    ]
  }

  before_hook "refresh_cluster_creds" {
    commands = ["init", "validate", "plan", "apply", "destroy", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "set -euo pipefail; TALOSCONFIG_SRC='${local.output_directory}/talosconfig'; KUBECONFIG_REPO='${local.output_directory}/kubeconfig'; KUBECONFIG_USER=\"$HOME/.kube/config\"; TALOSCONFIG_USER=\"$HOME/.talos/config\"; BOOTSTRAP_NODE='${local.cluster_config.node.public_ipv4}'; if [ -f \"$TALOSCONFIG_SRC\" ]; then mkdir -p \"$HOME/.kube\" \"$HOME/.talos\"; cp \"$TALOSCONFIG_SRC\" \"$TALOSCONFIG_USER\"; chmod 600 \"$TALOSCONFIG_USER\" || true; talosctl --talosconfig \"$TALOSCONFIG_SRC\" --nodes \"$BOOTSTRAP_NODE\" --endpoints \"$BOOTSTRAP_NODE\" kubeconfig \"$KUBECONFIG_REPO\" --merge=false --force >/dev/null 2>&1 || true; talosctl --talosconfig \"$TALOSCONFIG_SRC\" --nodes \"$BOOTSTRAP_NODE\" --endpoints \"$BOOTSTRAP_NODE\" kubeconfig \"$KUBECONFIG_USER\" --force >/dev/null 2>&1 || true; fi"
    ]
  }
}

inputs = {
  cluster_id           = local.cluster_config.cluster_name
  talosconfig          = dependency.talos_config.outputs.talosconfig
  client_configuration = dependency.talos_config.outputs.client_configuration
  control_plane_nodes  = dependency.talos_config.outputs.control_plane_ips
  cluster_endpoint     = dependency.talos_config.outputs.cluster_endpoint
  repo_root            = get_repo_root()
  output_directory     = local.output_directory
}
