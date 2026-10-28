locals {
  # Application/platform versions beyond base Talos/K8s
  applications = {
    cilium_version = "1.19.1" # Latest patch release
    # renovate: datasource=github-releases depName=fluxcd/flux2
    flux_version   = "2.10.0"
  }

  # GitOps configuration
  gitops = {
    flux_git_repository   = "https://github.com/sulibot/home-ops.git"
    flux_git_branch       = "main"
    # renovate: datasource=github-releases depName=fluxcd/flux2
    flux_version          = "2.10.0"
    # renovate: datasource=docker depName=ghcr.io/controlplaneio-fluxcd/charts/flux-operator
    flux_operator_version = "0.62.1"
  }
}
