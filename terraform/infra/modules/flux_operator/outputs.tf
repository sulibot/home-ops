output "namespace" {
  description = "Namespace where flux-operator is installed"
  value       = helm_release.flux_operator.namespace
}
