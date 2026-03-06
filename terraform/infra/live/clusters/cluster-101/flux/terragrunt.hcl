include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id
  context        = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals

  cluster_enabled        = try(local.cluster_config.enabled, true)
  bootstrap_mode         = trimspace(lower(get_env("TALOS_BOOTSTRAP_MODE", "false"))) == "true"
  app_versions           = local.context.app_versions
  secrets                = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/infra/live/common/secrets.sops.yaml"))
  cluster_kubeconfig     = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/kubeconfig"
  has_cluster_kubeconfig = fileexists(local.cluster_kubeconfig)
}

skip = !local.cluster_enabled

dependencies {
  paths = ["../bootstrap", "../cilium-bootstrap"]
}

dependency "bootstrap" {
  config_path = "../bootstrap"

  mock_outputs = {
    kubeconfig      = "mock"
    kubeconfig_path = "/tmp/mock-kubeconfig"
    cluster_ready   = true
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules//flux_stack"
}

inputs = {
  flux_operator_version = try(local.app_versions.gitops.flux_operator_version, "0.14.0")
  flux_version          = try(local.app_versions.gitops.flux_version, "2.4.0")

  git_repository = local.app_versions.gitops.flux_git_repository
  git_branch     = local.app_versions.gitops.flux_git_branch
  git_path       = "kubernetes/clusters/cluster-${local.tenant_id}"

  github_token       = local.secrets.github_token
  kubeconfig_path    = local.has_cluster_kubeconfig ? local.cluster_kubeconfig : dependency.bootstrap.outputs.kubeconfig_path
  kubeconfig_content = local.has_cluster_kubeconfig ? file(local.cluster_kubeconfig) : dependency.bootstrap.outputs.kubeconfig
  sops_age_key       = get_env("SOPS_AGE_KEY_FILE", "") != "" ? file(get_env("SOPS_AGE_KEY_FILE")) : ""
  repo_root          = get_repo_root()
  kubernetes_api_host = "fd00:${local.tenant_id}::10"
  bootstrap_mode      = local.bootstrap_mode
}
