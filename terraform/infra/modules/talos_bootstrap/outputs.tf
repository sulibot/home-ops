output "kubeconfig" {
  description = "Kubeconfig for cluster access"
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}
