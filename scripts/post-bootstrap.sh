#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "🚀 Starting Post-Bootstrap Configuration"
echo "=========================================="

KUBECONFIG="${KUBECONFIG:-./kubeconfig}"

if [ ! -f "$KUBECONFIG" ]; then
    echo "❌ Kubeconfig not found at $KUBECONFIG"
    exit 1
fi

# NOTE: CoreDNS configuration is now managed by Flux GitOps (kubernetes/apps/core/coredns)
# NOTE: Kopia PV/PVC are now managed by Flux GitOps with proper dependencies

# --- Stuck HelmRelease Detection and Fix ---
# Even with dependsOn in apps.yaml, there's still a race window where helm-controller's
# deployment is Available but the controller hasn't finished initializing its cache.
# This automated fix detects and resolves stuck HelmReleases.

echo "=========================================="
echo "🔧 Checking for stuck HelmReleases"
echo "=========================================="

# Loop for up to 10 minutes checking every 30 seconds
MAX_DURATION=600  # 10 minutes
CHECK_INTERVAL=30
START_TIME=$(date +%s)
FIX_APPLIED=false

while true; do
  ELAPSED=$(($(date +%s) - START_TIME))
  if [ $ELAPSED -ge $MAX_DURATION ]; then
    echo "⏱  Reached 10-minute timeout"
    break
  fi

  # Check if critical HelmReleases exist
  if ! kubectl --kubeconfig="$KUBECONFIG" get helmrelease -n ceph-csi ceph-csi-cephfs ceph-csi-rbd >/dev/null 2>&1; then
    echo "⏱  [$ELAPSED s] Waiting for Ceph CSI HelmReleases to be created..."
    sleep $CHECK_INTERVAL
    continue
  fi

  # Check if HelmReleases are ready
  CEPHFS_READY=$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease ceph-csi-cephfs -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  RBD_READY=$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease ceph-csi-rbd -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

  if [ "$CEPHFS_READY" = "True" ] && [ "$RBD_READY" = "True" ]; then
    echo "✓ Ceph CSI HelmReleases are ready"
    break
  fi

  # Check if stuck with observedGeneration: -1 (only check after 90 seconds)
  if [ $ELAPSED -ge 90 ] && [ "$FIX_APPLIED" = "false" ]; then
    # Check for any HelmRelease stuck with observedGeneration: -1
    STUCK_COUNT=$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease -A -o jsonpath='{range .items[*]}{.status.observedGeneration}{"\n"}{end}' 2>/dev/null | grep -c "\-1" || echo "0")

    if [ "$STUCK_COUNT" -gt "0" ]; then
      echo "⚠  [$ELAPSED s] Detected $STUCK_COUNT stuck HelmReleases (observedGeneration: -1)"
      echo "🔧 Applying fix: clean restart of helm-controller..."

      # Clean restart: scale down, wait for termination, scale up
      echo "   Scaling down helm-controller..."
      kubectl --kubeconfig="$KUBECONFIG" -n flux-system scale deployment helm-controller --replicas=0

      echo "   Waiting for pod to terminate..."
      kubectl --kubeconfig="$KUBECONFIG" -n flux-system wait --for=delete pod -l app=helm-controller --timeout=120s || true

      echo "   Scaling up helm-controller..."
      kubectl --kubeconfig="$KUBECONFIG" -n flux-system scale deployment helm-controller --replicas=1

      echo "   Waiting for deployment to be ready..."
      kubectl --kubeconfig="$KUBECONFIG" -n flux-system rollout status deployment helm-controller --timeout=120s

      echo "✓ Fix applied, helm-controller restarted cleanly"
      FIX_APPLIED=true
      # Continue loop to verify fix worked
    fi
  fi

  echo "⏱  [$ELAPSED s] Waiting for HelmReleases to reconcile..."
  sleep $CHECK_INTERVAL
done

# Final status check
CEPHFS_READY=$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease ceph-csi-cephfs -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
RBD_READY=$(kubectl --kubeconfig="$KUBECONFIG" get helmrelease ceph-csi-rbd -n ceph-csi -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

if [ "$CEPHFS_READY" = "True" ] && [ "$RBD_READY" = "True" ]; then
  echo "✓ Ceph CSI HelmReleases are ready"
else
  echo "⚠  Warning: Ceph CSI may still need manual intervention"
  echo "   Check with: kubectl get helmrelease -n ceph-csi"
fi

echo "=========================================="
echo "✓ Post-bootstrap complete!"
echo "=========================================="