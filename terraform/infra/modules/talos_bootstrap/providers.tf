# Provider configuration for Flux bootstrap

provider "flux" {
  kubernetes = {
    host                   = "https://[${var.control_plane_nodes[keys(var.control_plane_nodes)[0]].ipv6}]:6443"
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
