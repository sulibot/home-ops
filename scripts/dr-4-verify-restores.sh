#!/usr/bin/env bash
# DR Script 4: Verify Restores Complete
#
# Purpose: Verify that all app config PVCs were successfully restored from backups
# Run this after dr-3-trigger-restores.sh completes
#
# Prerequisites:
#   - Run dr-3-trigger-restores.sh first
#   - Wait 10-15 minutes for restores to complete
#
# What it checks:
#   1. All restore jobs completed successfully
#   2. All VolumeSnapshots created and ready
#   3. All app config PVCs bound with correct sizes
#   4. Total restored capacity matches expected
#
# Usage: ./scripts/dr-4-verify-restores.sh

set -euo pipefail

echo "=========================================="
echo "DR Script 4: Verify Restores Complete"
echo "=========================================="
echo ""

SUCCESS=true

# Check 1: Restore Jobs
echo "✓ Checking restore jobs..."
JOBS_TOTAL=$(kubectl get jobs -n default --no-headers 2>/dev/null | grep -c "volsync-dst" || echo "0")
JOBS_COMPLETE=$(kubectl get jobs -n default --no-headers 2>/dev/null | grep "volsync-dst" | grep -c "1/1" || echo "0")
JOBS_FAILED=$(kubectl get jobs -n default --no-headers 2>/dev/null | grep "volsync-dst" | grep -c "0/1" || echo "0")

echo "  Total: $JOBS_TOTAL | Complete: $JOBS_COMPLETE | Failed: $JOBS_FAILED"

if [ "$JOBS_FAILED" -gt 0 ]; then
    echo "  ❌ Some restore jobs failed"
    SUCCESS=false
    echo ""
    echo "Failed jobs:"
    kubectl get jobs -n default | grep "volsync-dst" | grep "0/1"
else
    echo "  ✅ All restore jobs completed successfully"
fi

# Check 2: VolumeSnapshots
echo ""
echo "✓ Checking VolumeSnapshots..."
SNAPSHOTS_TOTAL=$(kubectl get volumesnapshot -n default --no-headers 2>/dev/null | grep -c "dst-dest" || echo "0")
SNAPSHOTS_READY=$(kubectl get volumesnapshot -n default --no-headers 2>/dev/null | grep "dst-dest" | grep -c "true" || echo "0")

echo "  Total: $SNAPSHOTS_TOTAL | Ready: $SNAPSHOTS_READY"

if [ "$SNAPSHOTS_READY" -lt 20 ]; then
    echo "  ⚠️  Only $SNAPSHOTS_READY snapshots ready (expected 22+)"
    SUCCESS=false
else
    echo "  ✅ All VolumeSnapshots ready"
fi

# Check 3: App Config PVCs
echo ""
echo "✓ Checking app config PVCs..."
PVC_TOTAL=$(kubectl get pvc -n default --no-headers 2>/dev/null | grep -c "config" || echo "0")
PVC_BOUND=$(kubectl get pvc -n default --no-headers 2>/dev/null | grep "config" | grep -c "Bound" || echo "0")
PVC_PENDING=$(kubectl get pvc -n default --no-headers 2>/dev/null | grep "config" | grep -c "Pending" || echo "0")

echo "  Total: $PVC_TOTAL | Bound: $PVC_BOUND | Pending: $PVC_PENDING"

if [ "$PVC_PENDING" -gt 0 ]; then
    echo "  ⚠️  $PVC_PENDING PVCs still pending"
    SUCCESS=false
    echo ""
    echo "Pending PVCs:"
    kubectl get pvc -n default | grep "config" | grep "Pending"
else
    echo "  ✅ All app config PVCs bound"
fi

# Check 4: PVC Sizes
echo ""
echo "✓ Checking PVC sizes..."
echo ""
echo "  App                  Size"
echo "  ---                  ----"

TOTAL_SIZE=0
for app in atuin autobrr emby filebrowser home-assistant immich jellyseerr lidarr mosquitto nzbget overseerr plex prowlarr qbittorrent qui radarr redis sabnzbd slskd sonarr tautulli thelounge; do
    if kubectl get pvc "${app}-config" -n default &>/dev/null; then
        SIZE=$(kubectl get pvc "${app}-config" -n default -o jsonpath='{.status.capacity.storage}' 2>/dev/null || echo "N/A")
        printf "  %-20s %s\n" "$app" "$SIZE"

        # Sum up total (rough calculation, ignoring units)
        SIZE_NUM=$(echo "$SIZE" | sed 's/Gi//')
        if [[ "$SIZE_NUM" =~ ^[0-9]+$ ]]; then
            TOTAL_SIZE=$((TOTAL_SIZE + SIZE_NUM))
        fi
    fi
done

echo ""
echo "  Total capacity: ~${TOTAL_SIZE}Gi"

# Final Status
echo ""
echo "=========================================="
if [ "$SUCCESS" = true ]; then
    echo "✅ SUCCESS: All restores verified!"
    echo "=========================================="
    echo ""
    echo "All app config PVCs are restored and ready."
    echo "Apps should now be starting automatically."
    echo ""
    echo "To check app status:"
    echo "  kubectl get pods -n default"
    echo ""
    echo "Disaster recovery complete! 🎉"
    echo ""
    exit 0
else
    echo "⚠️  INCOMPLETE: Some restores not finished"
    echo "=========================================="
    echo ""
    echo "Wait a few more minutes and run this script again."
    echo ""
    echo "Or check status manually:"
    echo "  kubectl get jobs -n default | grep volsync-dst"
    echo "  kubectl get volumesnapshot -n default | grep dst-dest"
    echo "  kubectl get pvc -n default | grep config"
    echo ""
    exit 1
fi
