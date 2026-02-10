# Flux Operator Module
# Deploys flux-operator via Helm, which manages Flux controllers
# This is Phase 1 of the two-phase Flux deployment

# Wait for Cilium CNI to be ready before deploying flux-operator
# This prevents flux-operator from crashlooping while Cilium is still initializing
# Cilium is installed via Talos inline manifests and takes ~4 minutes for image pull + init
resource "null_resource" "wait_cilium_ready" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for Cilium CNI to be ready before deploying flux-operator..."

      # Wait for Cilium DaemonSet to exist (created by Talos inline manifests)
      echo "  Checking for Cilium DaemonSet..."
      timeout 120 bash -c '
        until kubectl --kubeconfig="$KUBECONFIG" get daemonset cilium -n kube-system >/dev/null 2>&1; do
          echo "    ⏳ Waiting for Cilium DaemonSet to be created..."
          sleep 5
        done
      '
      echo "  ✓ Cilium DaemonSet exists"

      # Wait for Cilium pods to be ready (handles image pull delays)
      echo "  Waiting for Cilium pods to be ready..."
      kubectl --kubeconfig="$KUBECONFIG" wait \
        --for=condition=Ready \
        pods -l k8s-app=cilium \
        -n kube-system \
        --timeout=300s

      echo "  ✓ Cilium pods are ready"

      # Wait for cilium-operator deployment to be available
      echo "  Waiting for cilium-operator deployment..."
      kubectl --kubeconfig="$KUBECONFIG" wait \
        --for=condition=Available \
        deployment cilium-operator \
        -n kube-system \
        --timeout=120s

      # Verify Cilium has correct routing configuration (from Git repo values.yaml)
      # This ensures ClusterIP services work before flux-operator starts
      echo "  Verifying Cilium routing configuration..."
      CURRENT_SKIP=$(kubectl --kubeconfig="$KUBECONFIG" get configmap cilium-config -n kube-system -o jsonpath='{.data.direct-routing-skip-unreachable}')
      if [ "$CURRENT_SKIP" != "true" ]; then
        echo "    ⚠ Cilium missing directRoutingSkipUnreachable fix, patching..."
        kubectl --kubeconfig="$KUBECONFIG" patch configmap cilium-config -n kube-system --type=merge -p '{"data":{"direct-routing-skip-unreachable":"true"}}'
        kubectl --kubeconfig="$KUBECONFIG" rollout restart ds/cilium -n kube-system
        kubectl --kubeconfig="$KUBECONFIG" rollout status ds/cilium -n kube-system --timeout=120s
        echo "    ✓ Cilium restarted with routing fix"
      else
        echo "    ✓ Cilium routing configuration correct"
      fi

      echo "✓ Cilium CNI is fully ready - flux-operator can now start safely"
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

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

  # Add startup probe with high tolerance as safety net
  # This prevents restart loops if there are transient connectivity issues
  # even after Cilium is ready (e.g., brief DNS resolution delays)
  values = [
    yamlencode({
      # Startup probe for flux-operator deployment
      startupProbe = {
        httpGet = {
          path = "/healthz"
          port = 8081
        }
        initialDelaySeconds = 10
        periodSeconds       = 5
        failureThreshold    = 60  # 10s + (60 × 5s) = 310s total tolerance
        successThreshold    = 1
        timeoutSeconds      = 3
      }
    })
  ]

  # Wait for Cilium to be ready before deploying
  depends_on = [null_resource.wait_cilium_ready]
}
