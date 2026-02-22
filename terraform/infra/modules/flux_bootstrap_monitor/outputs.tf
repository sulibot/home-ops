output "tier_0_ready" {
  description = "Tier 0 (Foundation) check completed (status logged inside provisioner)"
  value       = null_resource.check_tier_0.id != "" ? "Checked" : "Unknown"
}

output "tier_1_ready" {
  description = "Tier 1 (Infrastructure) check completed (status logged inside provisioner)"
  value       = null_resource.check_tier_1.id != "" ? "Checked" : "Unknown"
}

output "bootstrap_complete" {
  description = "Bootstrap wait completed successfully (tiers ready; checked inside wait_bootstrap_complete provisioner)"
  value       = null_resource.wait_bootstrap_complete.id != ""
}

output "bootstrap_override_removed" {
  description = "Whether the bootstrap override ConfigMap has been deleted (apps now on production defaults)"
  value       = var.auto_switch_intervals ? length(null_resource.delete_bootstrap_configmap) > 0 : false
}
