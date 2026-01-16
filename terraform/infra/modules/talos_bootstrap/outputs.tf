output "kubeconfig" {
  description = "Kubeconfig for cluster access"
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "post_bootstrap_instructions" {
  description = "Manual steps required after cluster bootstrap"
  value = <<-EOT

    ============================================================================
    CLUSTER BOOTSTRAP COMPLETE
    ============================================================================

    IMPORTANT: Manual steps required to complete the cluster setup:

    1. Reclaim Kopia Repository (200GB backup storage)
       The Kopia repository PV and PVC are excluded from GitOps to prevent
       accidental data loss during cluster rebuilds.

       To reattach the existing Kopia repository:

       kubectl apply -f kubernetes/apps/data/kopia/app/kopia-repository-pv.yaml
       kubectl apply -f kubernetes/apps/data/kopia/app/kopia-repository-pvc.yaml

       This will reconnect the 200GB CephFS backup repository and allow the
       Kopia server in volsync-system to start.

    2. Verify all pods are running:
       kubectl get pods -A

    ============================================================================
  EOT
}
