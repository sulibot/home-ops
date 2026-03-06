output "namespace" {
  description = "Namespace where flux-operator is installed"
  value       = module.operator.namespace
}

output "flux_ready" {
  description = "Indicates Flux is fully deployed and ready"
  value       = module.instance.flux_ready
}

output "sync_path" {
  description = "Git path being synced by Flux"
  value       = module.instance.sync_path
}

output "tier_0_ready" {
  description = "Tier 0 check completion status"
  value       = var.bootstrap_mode ? module.bootstrap_monitor[0].tier_0_ready : "Skipped (steady-state mode)"
}

output "tier_1_ready" {
  description = "Tier 1 check completion status"
  value       = var.bootstrap_mode ? module.bootstrap_monitor[0].tier_1_ready : "Skipped (steady-state mode)"
}

output "bootstrap_complete" {
  description = "Bootstrap wait completed successfully"
  value       = var.bootstrap_mode ? module.bootstrap_monitor[0].bootstrap_complete : true
}
