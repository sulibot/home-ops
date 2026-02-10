# Flux Operator Module
# Deploys flux-operator via Helm, which manages Flux controllers
# This is Phase 1 of the two-phase Flux deployment

resource "helm_release" "flux_operator" {
  name       = "flux-operator"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-operator"
  version    = var.flux_operator_version

  create_namespace = true
  wait             = false  # Don't wait - flux-instance stage will handle readiness checks
  wait_for_jobs    = false
  timeout          = 600

  # Cleanup on failure to prevent stuck resources
  cleanup_on_fail = true

  # Force resource updates
  force_update = false
}
