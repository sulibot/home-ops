include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id
  context        = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals

  cluster_enabled        = try(local.cluster_config.enabled, true)
  bootstrap_mode         = trimspace(lower(get_env("TALOS_BOOTSTRAP_MODE", "false"))) == "true"
  cnpg_new_db            = trimspace(lower(get_env("CNPG_NEW_DB", "false"))) == "true"
  cnpg_restore_mode      = trimspace(upper(get_env("CNPG_RESTORE_MODE", local.cnpg_new_db ? "NEW_DB" : "RESTORE_REQUIRED")))
  cnpg_restore_method    = trimspace(lower(get_env("CNPG_RESTORE_METHOD", "auto")))
  cnpg_backup_max_age_hours = tonumber(get_env("CNPG_BACKUP_MAX_AGE_HOURS", "36"))
  cnpg_stale_backup_max_age_minutes = tonumber(get_env("CNPG_STALE_BACKUP_MAX_AGE_MINUTES", "45"))
  cnpg_storage_size      = trimspace(get_env("CNPG_STORAGE_SIZE", "60Gi"))
  app_versions           = local.context.app_versions
  secrets                = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/infra/live/common/secrets.sops.yaml"))
  cluster_kubeconfig     = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/kubeconfig"
  cluster_talosconfig    = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/talosconfig"
  bootstrap_node_ipv4    = "10.${local.tenant_id}.0.11"
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

  before_hook "refresh_kubeconfig" {
    commands = ["init", "validate", "plan", "apply", "destroy", "refresh", "import"]
    execute = [
      "bash",
      "-lc",
      "set -euo pipefail; if [ -f '${local.cluster_talosconfig}' ]; then talosctl --talosconfig '${local.cluster_talosconfig}' --nodes '${local.bootstrap_node_ipv4}' --endpoints '${local.bootstrap_node_ipv4}' kubeconfig '${local.cluster_kubeconfig}' --merge=false --force >/dev/null 2>&1 || true; fi"
    ]
  }
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
  cnpg_new_db         = local.cnpg_new_db
  cnpg_restore_mode   = local.cnpg_restore_mode
  cnpg_restore_method = local.cnpg_restore_method
  cnpg_backup_max_age_hours = local.cnpg_backup_max_age_hours
  cnpg_stale_backup_max_age_minutes = local.cnpg_stale_backup_max_age_minutes
  cnpg_storage_size   = local.cnpg_storage_size
}
