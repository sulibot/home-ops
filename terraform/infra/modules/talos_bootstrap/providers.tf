# Provider configuration for Flux bootstrap

locals {
  # Safe provider config - use defaults if control_plane_nodes is empty (e.g., during destroy)
  first_cp_host = length(var.control_plane_nodes) > 0 ? "https://[${var.control_plane_nodes[keys(var.control_plane_nodes)[0]].ipv6}]:6443" : "https://localhost:6443"
  cluster_host  = var.cluster_endpoint != "" ? var.cluster_endpoint : local.first_cp_host
}

provider "flux" {
  kubernetes = {
    host                   = local.cluster_host
    client_certificate     = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.ca_certificate)
  }

  git = {
    url    = var.flux_git_repository
    branch = var.flux_git_branch

    # HTTP authentication with GitHub token from SOPS-encrypted secrets
    http = {
      username = "git"
      password = var.flux_github_token
    }
  }
}
