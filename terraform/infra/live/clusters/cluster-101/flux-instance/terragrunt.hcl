include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../flux-operator"]
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

dependency "flux_operator" {
  config_path = "../flux-operator"

  mock_outputs = {
    namespace = "flux-system"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/flux_instance"
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  app_versions   = read_terragrunt_config(find_in_parent_folders("common/application-versions.hcl")).locals
  secrets        = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/infra/live/common/secrets.sops.yaml"))
}

inputs = {
  flux_version       = try(local.app_versions.gitops.flux_version, "2.4.0")
  git_repository     = local.app_versions.gitops.flux_git_repository
  git_branch         = local.app_versions.gitops.flux_git_branch
  git_path           = "kubernetes/clusters/cluster-${local.cluster_config.cluster_id}"
  github_token       = local.secrets.github_token
  kubeconfig_path    = dependency.bootstrap.outputs.kubeconfig_path
  kubeconfig_content = dependency.bootstrap.outputs.kubeconfig
  sops_age_key       = get_env("SOPS_AGE_KEY_FILE", "") != "" ? file(get_env("SOPS_AGE_KEY_FILE")) : ""
  repo_root          = get_repo_root()
}
