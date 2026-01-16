# Bootstrap Flux GitOps
# This installs Flux and configures it to sync from the Git repository

resource "flux_bootstrap_git" "this" {
  # Only bootstrap if git repository is provided
  count = var.flux_git_repository != "" ? 1 : 0

  # Path in Git repo where Flux manifests live
  path = "kubernetes/clusters/cluster-${var.cluster_id}"

  # Install Flux v2.7.5 with healthCheckExprs support
  version = "v2.7.5"

  # Component versions that match Flux v2.7.5
  components_extra = [
    "image-reflector-controller",
    "image-automation-controller"
  ]

  lifecycle {
    # During destroy, skip Flux cleanup via Kubernetes API
    # Flux resources are removed when VMs are destroyed anyway
    # Manual state cleanup required: terragrunt state rm 'flux_bootstrap_git.this[0]'
    ignore_changes = all
  }

  # Depends on kubeconfig being available
  depends_on = [
    talos_cluster_kubeconfig.cluster,
    null_resource.sops_age_secret
  ]
}
