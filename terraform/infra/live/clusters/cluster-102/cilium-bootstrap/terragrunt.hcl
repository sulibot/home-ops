include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id

  cluster_enabled        = try(local.cluster_config.enabled, true)
  bootstrap_mode         = trimspace(lower(get_env("TALOS_BOOTSTRAP_MODE", "false"))) == "true"
  bootstrap_run_token    = local.bootstrap_mode ? formatdate("YYYYMMDDhhmmss", timestamp()) : ""
  cluster_kubeconfig     = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/kubeconfig"
  has_cluster_kubeconfig = fileexists(local.cluster_kubeconfig)
  kubernetes_api_ready  = local.has_cluster_kubeconfig && trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.cluster_kubeconfig}' timeout 8 kubectl get --raw=/readyz >/dev/null 2>&1 && echo true || echo false"
  )) == "true"
}

# Bootstrap unit runs for first build, and can be forced in explicit bootstrap mode.
skip = !local.cluster_enabled || (!local.bootstrap_mode && local.kubernetes_api_ready)

dependencies {
  paths = ["../bootstrap"]
}

dependency "bootstrap" {
  config_path = "../bootstrap"

  mock_outputs = {
    kubeconfig_path = "/tmp/mock-kubeconfig"
    cluster_ready   = true
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/cilium_bootstrap"
}

inputs = {
  kubeconfig_path     = local.has_cluster_kubeconfig ? local.cluster_kubeconfig : dependency.bootstrap.outputs.kubeconfig_path
  bootstrap_run_token = local.bootstrap_run_token
  repo_root           = get_repo_root()
}
