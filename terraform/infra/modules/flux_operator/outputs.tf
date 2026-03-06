output "namespace" {
  description = "Namespace where flux-operator is installed"
  value       = helm_release.flux_operator.namespace
}

output "ready_id" {
  description = "Apply-time signal that flux-operator release has been created"
  value       = helm_release.flux_operator.id
}
