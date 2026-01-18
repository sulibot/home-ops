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
  wait             = true
  wait_for_jobs    = true
  timeout          = 600  # Increased from 300 to allow more time for operator readiness

  # Cleanup on failure to prevent stuck resources
  cleanup_on_fail = true

  # Force resource updates
  force_update = false
}
