locals {
  # Application/platform versions beyond base Talos/K8s
  applications = {
    cilium_version = "1.19.0"  # Latest feature release (Feb 2025) - 2934+ commits, 1010+ contributors
    flux_version   = "2.7.5"  # Latest stable - includes healthCheckExprs support
  }

  # GitOps configuration
  gitops = {
    flux_git_repository    = "https://github.com/sulibot/home-ops.git"
    flux_git_branch        = "main"
    flux_version           = "2.7.5"  # Latest stable - includes healthCheckExprs support
    flux_operator_version  = "0.41.1"  # Latest version (Feb 2026) - supports Flux v2.7.5+
  }
}
