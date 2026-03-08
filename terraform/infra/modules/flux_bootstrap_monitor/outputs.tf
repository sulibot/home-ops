output "tier_0_ready" {
  description = "Tier 0 prerequisite checks completed (covered by CRD gate and in-cluster capability job)"
  value       = null_resource.wait_crd_established.id != "" ? "Checked" : "Unknown"
}

output "tier_1_ready" {
  description = "Tier 1 prerequisite checks completed (covered by restore orchestration and capability job)"
  value       = null_resource.cnpg_restore.id != "" ? "Checked" : "Unknown"
}

output "bootstrap_complete" {
  description = "Bootstrap wait completed successfully (tiers ready; checked inside wait_bootstrap_complete provisioner)"
  value       = null_resource.wait_bootstrap_complete.id != ""
}
