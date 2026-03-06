terraform {
  # Terragrunt remote_state requires a backend block in the root module.
  backend "local" {}
}

module "operator" {
  source = "../flux_operator"

  flux_operator_version = var.flux_operator_version
  kubeconfig_path       = var.kubeconfig_path
  kubeconfig_content    = var.kubeconfig_content
  kubernetes_api_host   = var.kubernetes_api_host
  region                = var.region
}

module "instance" {
  source = "../flux_instance"

  flux_version        = var.flux_version
  git_repository      = var.git_repository
  git_branch          = var.git_branch
  git_path            = var.git_path
  sops_age_key        = var.sops_age_key
  kubeconfig_path     = var.kubeconfig_path
  kubeconfig_content  = var.kubeconfig_content
  kubernetes_api_host = var.kubernetes_api_host
  github_token        = var.github_token
  repo_root           = var.repo_root
  region              = var.region

  depends_on = [module.operator]
}

module "bootstrap_monitor" {
  count  = var.bootstrap_mode ? 1 : 0
  source = "../flux_bootstrap_monitor"

  kubeconfig_path           = var.kubeconfig_path
  bootstrap_timeout_seconds = var.bootstrap_timeout_seconds
  cnpg_new_db               = var.cnpg_new_db
  region                    = var.region

  depends_on = [module.instance]
}
