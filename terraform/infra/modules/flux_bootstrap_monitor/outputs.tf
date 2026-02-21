output "tier_0_ready" {
  description = "Tier 0 (Foundation) ready status"
  value = try(
    [for c in data.kubernetes_resource.tier_0_foundation.object.status.conditions :
      c.status if c.type == "Ready"
    ][0],
    "Unknown"
  )
}

output "tier_1_ready" {
  description = "Tier 1 (Infrastructure) ready status"
  value = try(
    [for c in data.kubernetes_resource.tier_1_infrastructure.object.status.conditions :
      c.status if c.type == "Ready"
    ][0],
    "Unknown"
  )
}

output "bootstrap_complete" {
  description = "Whether bootstrap has completed (tiers ready; critical app checks run inside provisioner)"
  value = (
    try([for c in data.kubernetes_resource.tier_0_foundation.object.status.conditions : c.status if c.type == "Ready"][0], "") == "True" &&
    try([for c in data.kubernetes_resource.tier_1_infrastructure.object.status.conditions : c.status if c.type == "Ready"][0], "") == "True"
  )
}

output "bootstrap_override_removed" {
  description = "Whether the bootstrap override ConfigMap has been deleted (apps now on production defaults)"
  value       = var.auto_switch_intervals ? length(null_resource.delete_bootstrap_configmap) > 0 : false
}
