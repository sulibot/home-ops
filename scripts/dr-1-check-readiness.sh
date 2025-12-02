#!/usr/bin/env bash
# DR Script 1: Check Cluster Readiness for Restore
#
# Purpose: Verify all prerequisites are met before running Kopia repository reclaim
# Run this first after a cluster rebuild to ensure infrastructure is ready
#
# Prerequisites:
#   - Cluster is running
#   - Flux is deployed
#   - kubectl context is set to correct cluster
#
# Usage: ./scripts/dr-1-check-readiness.sh

set -euo pipefail

echo "=========================================="
echo "DR Script 1: Cluster Readiness Check"
echo "=========================================="
echo ""

READY=true

# Check 1: Flux Core Components
echo "✓ Checking Flux core components..."
if flux get ks flux-system 2>/dev/null | grep -q "True"; then
    echo "  ✅ flux-system: Ready"
else
    echo "  ❌ flux-system: Not Ready"
    READY=false
fi

# Check 2: Essential Kustomizations
echo ""
echo "✓ Checking essential kustomizations..."
for ks in cert-manager external-secrets ceph-csi volsync; do
    if flux get ks "$ks" 2>/dev/null | grep -q "True"; then
        echo "  ✅ $ks: Ready"
    else
        echo "  ❌ $ks: Not Ready (waiting...)"
        READY=false
    fi
done

# Check 3: Storage Classes
echo ""
echo "✓ Checking storage classes..."
for sc in csi-cephfs-config-sc csi-cephfs-backups-sc; do
    if kubectl get sc "$sc" &>/dev/null; then
        echo "  ✅ $sc: Available"
    else
        echo "  ❌ $sc: Missing"
        READY=false
    fi
done

# Check 4: Snapshot Class
echo ""
echo "✓ Checking snapshot class..."
if kubectl get volumesnapshotclass csi-cephfs-config-snapclass &>/dev/null; then
    echo "  ✅ csi-cephfs-config-snapclass: Available"
else
    echo "  ❌ csi-cephfs-config-snapclass: Missing"
    READY=false
fi

# Check 5: Ceph-CSI Pods
echo ""
echo "✓ Checking Ceph-CSI pods..."
CEPHFS_PODS=$(kubectl get pods -n ceph-csi -l app=ceph-csi-cephfs --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [ "$CEPHFS_PODS" -ge 3 ]; then
    echo "  ✅ CephFS CSI pods: $CEPHFS_PODS Running"
else
    echo "  ❌ CephFS CSI pods: Only $CEPHFS_PODS Running (need 3+)"
    READY=false
fi

# Check 6: Volsync Operator
echo ""
echo "✓ Checking Volsync operator..."
if kubectl get pods -n volsync-system --no-headers 2>/dev/null | grep -q "Running"; then
    echo "  ✅ Volsync operator: Running"
else
    echo "  ❌ Volsync operator: Not Running"
    READY=false
fi

# Check 7: Volsync Secrets (from ExternalSecrets)
echo ""
echo "✓ Checking volsync secrets..."
SECRET_COUNT=$(kubectl get secrets -n default 2>/dev/null | grep -c "volsync-secret" || echo "0")
if [ "$SECRET_COUNT" -ge 20 ]; then
    echo "  ✅ Volsync secrets: $SECRET_COUNT found"
else
    echo "  ⚠️  Volsync secrets: Only $SECRET_COUNT found (apps may still be deploying)"
    # Not marking as failed - secrets populate as apps reconcile
fi

# Final Status
echo ""
echo "=========================================="
if [ "$READY" = true ]; then
    echo "✅ READY: All prerequisites met!"
    echo ""
    echo "Next step:"
    echo "  ./scripts/dr-2-reclaim-kopia-repository.sh"
    echo ""
    exit 0
else
    echo "❌ NOT READY: Prerequisites not met"
    echo ""
    echo "Wait for components to become Ready, then run this script again."
    echo ""
    echo "To monitor progress:"
    echo "  watch flux get ks --all-namespaces"
    echo ""
    exit 1
fi
