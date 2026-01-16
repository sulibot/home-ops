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

# --- CoreDNS Patching ---
echo "🔧 Checking CoreDNS configuration..."

# Wait for CoreDNS ConfigMap
echo "   Waiting for CoreDNS ConfigMap..."
timeout 60s bash -c "until kubectl --kubeconfig='$KUBECONFIG' -n kube-system get configmap coredns >/dev/null 2>&1; do sleep 2; done"

# Patch CoreDNS to use Talos host DNS forwarder (fixes resolution issues in some setups)
echo "   Patching CoreDNS to use host DNS forwarder (169.254.116.108)..."
kubectl --kubeconfig="$KUBECONFIG" -n kube-system patch configmap coredns --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    health {\n        lameduck 5s\n    }\n    ready\n    log . {\n        class error\n    }\n    prometheus :9153\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    forward . 169.254.116.108 {\n       max_concurrent 1000\n    }\n    cache 30 {\n        denial 9984 30\n    }\n    loop\n    reload\n    loadbalance\n}\n"}}'

echo "   Restarting CoreDNS..."
kubectl --kubeconfig="$KUBECONFIG" -n kube-system rollout restart deployment coredns
kubectl --kubeconfig="$KUBECONFIG" -n kube-system rollout status deployment coredns --timeout=60s
echo "✓ CoreDNS patched and restarted"

# --- Stuck HelmRelease Detection and Fix ---
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

      # Clean restart as recommended by Gemini: scale down, wait for termination, scale up
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

# --- Kopia Repository Reclamation ---
echo "=========================================="
echo "🗄  Reclaiming Kopia repository"
echo "=========================================="

# Wait for Ceph CSI pods to be running
echo "   Waiting for Ceph CSI pods to be running..."
RETRIES=30
ATTEMPT=0
while [ $ATTEMPT -lt $RETRIES ]; do
  CEPHFS_PODS=$(kubectl --kubeconfig="$KUBECONFIG" get pods -n ceph-csi -l app=ceph-csi-cephfs --field-selector=status.phase=Running 2>/dev/null | grep -c Running || echo 0)
  if [ "$CEPHFS_PODS" -gt 0 ]; then
    echo "✓ Ceph CSI CephFS pods are running"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  sleep 5
done

if [ $ATTEMPT -eq $RETRIES ]; then
  echo "⚠  Warning: Ceph CSI pods not running after 150s, Kopia repository may not bind"
fi

# Apply PV and PVC
echo "   Applying Kopia repository PV and PVC..."
# Note: Adjust paths if running from a different directory
if [ -f "kubernetes/apps/data/kopia/app/kopia-repository-pv.yaml" ]; then
    kubectl --kubeconfig="$KUBECONFIG" apply -f kubernetes/apps/data/kopia/app/kopia-repository-pv.yaml
    kubectl --kubeconfig="$KUBECONFIG" apply -f kubernetes/apps/data/kopia/app/kopia-repository-pvc.yaml

    # Wait for PVC to bind
    echo "   Waiting for Kopia PVC to bind..."
    timeout 60s bash -c "until kubectl --kubeconfig='$KUBECONFIG' get pvc kopia -n volsync-system -o jsonpath='{.status.phase}' | grep -q Bound; do sleep 2; done"
    echo "✓ Kopia repository PVC bound successfully"
else
    echo "⚠ Warning: Kopia manifest files not found, skipping reclamation."
fi

echo "=========================================="
echo "✓ Post-bootstrap complete!"
echo "=========================================="