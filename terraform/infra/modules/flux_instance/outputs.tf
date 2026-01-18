output "flux_ready" {
  description = "Indicates Flux is fully deployed and ready"
  value       = true

  depends_on = [null_resource.wait_helm_cache_ready]
}

output "sync_path" {
  description = "Git path being synced by Flux"
  value       = var.git_path
}
