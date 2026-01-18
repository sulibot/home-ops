locals {
  # Application/platform versions beyond base Talos/K8s
  applications = {
    cilium_version = "1.18.4"
    flux_version   = "2.7.5"  # Latest stable - includes healthCheckExprs support
  }

  # GitOps configuration
  gitops = {
    flux_git_repository    = "https://github.com/sulibot/home-ops.git"
    flux_git_branch        = "main"
    flux_version           = "2.7.5"  # Latest stable - includes healthCheckExprs support
    flux_operator_version  = "0.38.1"  # Latest version (Dec 2025) - supports Flux v2.7.5+
  }
}
