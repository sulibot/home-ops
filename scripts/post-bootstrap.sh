#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "🚀 Post-Bootstrap Verification"
echo "=========================================="

KUBECONFIG="${KUBECONFIG:-./kubeconfig}"

if [ ! -f "$KUBECONFIG" ]; then
    echo "❌ Kubeconfig not found at $KUBECONFIG"
    exit 1
fi

# NOTE: CoreDNS configuration is managed by Flux GitOps (kubernetes/apps/core/coredns)
# NOTE: Kopia PV/PVC are managed by Flux GitOps with proper dependencies
# NOTE: Helm cache readiness is now guaranteed by Terraform canary testing

echo "=========================================="
echo "🔍 Verifying Flux Configuration"
echo "=========================================="

# Verify flux-system is resumed (safety check)
SUSPENDED=$(kubectl --kubeconfig="$KUBECONFIG" get kustomization flux-system -n flux-system -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "")

if [ "$SUSPENDED" = "true" ]; then
    echo "⚠️  WARNING: flux-system is still suspended!"
    echo "   This indicates the helm cache canary may have failed."
    echo "   Resuming manually to allow apps to deploy..."
    kubectl --kubeconfig="$KUBECONFIG" patch kustomization flux-system -n flux-system \
      --type=merge -p '{"spec":{"suspend":false}}'
    echo "✓ flux-system resumed"
else
    echo "✓ flux-system is active"
fi

# Verify no canary resources left behind
CANARY_COUNT=$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease,helmrepository -n flux-system -o name 2>/dev/null | grep -c "flux-cache-canary\|podinfo" || echo "0")

if [ "$CANARY_COUNT" -gt "0" ]; then
    echo "⚠️  Found leftover canary resources - cleaning up..."
    kubectl --kubeconfig="$KUBECONFIG" delete helmrelease flux-cache-canary -n flux-system --ignore-not-found=true || true
    kubectl --kubeconfig="$KUBECONFIG" delete helmrepository podinfo -n flux-system --ignore-not-found=true || true
    echo "✓ Canary cleanup complete"
else
    echo "✓ No canary resources found (cleanup successful)"
fi

echo "=========================================="
echo "✓ Post-bootstrap verification complete!"
echo "=========================================="