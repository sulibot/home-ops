include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../bootstrap"]
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
  source = "../../../../modules/flux_operator"
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  app_versions   = read_terragrunt_config(find_in_parent_folders("common/application-versions.hcl")).locals
}

inputs = {
  flux_operator_version = try(local.app_versions.gitops.flux_operator_version, "0.14.0")
  kubeconfig_path       = dependency.bootstrap.outputs.kubeconfig_path
  kubeconfig_content    = dependency.bootstrap.outputs.kubeconfig
}
