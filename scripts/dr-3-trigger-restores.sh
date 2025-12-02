#!/usr/bin/env bash
# DR Script 3: Trigger All Restores
#
# Purpose: Trigger Volsync restores for all 22 applications from Kopia backups
# This creates VolumeSnapshots which populate app config PVCs via volume populator
#
# Prerequisites:
#   - Run dr-2-reclaim-kopia-repository.sh first
#   - Kopia repository PVC is Bound (200Gi)
#   - ReplicationDestination resources exist for all apps
#
# What it does:
#   1. Patches all ReplicationDestination resources to trigger manual restore
#   2. Volsync starts restore jobs (one per app)
#   3. Each restore job:
#      - Connects to Kopia repository
#      - Restores latest snapshot to temp PVC
#      - Creates VolumeSnapshot from restored data
#   4. Volume populator creates app config PVCs from snapshots
#
# Timeline:
#   - Restore jobs start: ~10 seconds
#   - Restore jobs complete: ~5-10 minutes (depends on data size)
#   - VolumeSnapshots created: ~1 minute after job completion
#   - App config PVCs bound: ~1 minute after snapshots ready
#   - Total time: ~10-15 minutes for all apps
#
# Result: 22 app config PVCs populated with data from backups
#
# Usage: ./scripts/dr-3-trigger-restores.sh

set -euo pipefail

echo "=========================================="
echo "DR Script 3: Trigger All Restores"
echo "=========================================="
echo ""

# Check prerequisites
echo "✓ Checking prerequisites..."

# Check Kopia PVC exists and is Bound
if ! kubectl get pvc kopia -n default &>/dev/null; then
    echo "❌ ERROR: Kopia PVC not found"
    echo "   Run: ./scripts/dr-2-reclaim-kopia-repository.sh"
    exit 1
fi

PVC_STATUS=$(kubectl get pvc kopia -n default -o jsonpath='{.status.phase}')
if [ "$PVC_STATUS" != "Bound" ]; then
    echo "❌ ERROR: Kopia PVC is not Bound (status: $PVC_STATUS)"
    exit 1
fi

echo "  ✅ Kopia repository PVC: Bound"

# Check ReplicationDestinations exist
RD_COUNT=$(kubectl get replicationdestination -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$RD_COUNT" -lt 20 ]; then
    echo "  ⚠️  Only $RD_COUNT ReplicationDestinations found (expected 22+)"
    echo "     Waiting for Flux to reconcile apps..."
    sleep 10
fi

echo "  ✅ Found $RD_COUNT ReplicationDestinations"
echo ""

# Trigger restores
echo "✓ Triggering manual restores for all apps..."
echo ""

TIMESTAMP=$(date +%Y%m%d%H%M%S)
RESTORE_COUNT=0

for rd in $(kubectl get replicationdestination -n default -o name); do
  app=$(echo "$rd" | sed 's|.*/||;s/-dst$//')
  echo "  Triggering restore: $app"
  kubectl patch "$rd" -n default --type=merge -p "{\"spec\":{\"trigger\":{\"manual\":\"restore-${TIMESTAMP}\"}}}" &>/dev/null
  ((RESTORE_COUNT++))
done

echo ""
echo "=========================================="
echo "✅ Triggered $RESTORE_COUNT restores at $TIMESTAMP"
echo "=========================================="
echo ""

# Monitor progress
echo "Monitoring restore progress..."
echo ""
echo "Waiting 30 seconds for restore jobs to start..."
sleep 30

# Check restore jobs
JOBS_RUNNING=$(kubectl get jobs -n default --no-headers 2>/dev/null | grep -c "volsync-dst" || echo "0")
echo "  Restore jobs running: $JOBS_RUNNING"

echo ""
echo "To monitor progress in real-time:"
echo ""
echo "  # Watch restore jobs"
echo "  watch 'kubectl get jobs -n default | grep volsync-dst'"
echo ""
echo "  # Watch VolumeSnapshots being created"
echo "  watch 'kubectl get volumesnapshot -n default | grep dst-dest'"
echo ""
echo "  # Watch app config PVCs becoming Bound"
echo "  watch 'kubectl get pvc -n default | grep config'"
echo ""
echo "Expected timeline:"
echo "  - Now:        Restore jobs running"
echo "  - T+5-10min:  Restore jobs complete, VolumeSnapshots created"
echo "  - T+10-15min: All app config PVCs Bound and ready"
echo ""
echo "When all PVCs are Bound, apps will start automatically."
echo ""
echo "To verify completion later:"
echo "  ./scripts/dr-4-verify-restores.sh"
echo ""
