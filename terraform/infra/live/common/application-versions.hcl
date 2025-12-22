locals {
  # Application/platform versions beyond base Talos/K8s
  applications = {
    cilium_version = "1.18.4"
    flux_version   = "2.4.0"
  }

  # GitOps configuration
  gitops = {
    flux_git_repository = "https://github.com/sulibot/home-ops.git"
    flux_git_branch     = "main"
  }
}
