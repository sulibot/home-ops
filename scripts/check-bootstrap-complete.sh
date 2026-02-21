#!/usr/bin/env bash
# scripts/check-bootstrap-complete.sh
# Returns 0 when safe to switch to steady-state intervals
# Combines tier checks with specific critical app checks
# Maximum wait time: 15 minutes

set -e

echo "🚀 Checking bootstrap status..."

# Calculate timeout (15 minutes from now)
TIMEOUT_SECONDS=900  # 15 minutes
START_TIME=$(date +%s)

check_timeout() {
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
    echo ""
    echo "⏰ Timeout: Bootstrap check exceeded 15 minutes"
    echo "❌ Some components may not be ready yet"
    echo "   You may need to wait longer or investigate issues"
    exit 1
  fi
}

# MUST HAVE: Tier 0 (Foundation) Ready
echo "Checking Tier 0 (Foundation)..."
while ! kubectl get kustomization -n flux-system tier-0-foundation \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
  check_timeout
  echo "  ⏳ Tier 0 not ready yet, waiting 10s..."
  sleep 10
done
echo "✅ Tier 0 (Foundation) Ready"

# MUST HAVE: Tier 1 (Infrastructure) Ready
echo "Checking Tier 1 (Infrastructure)..."
while ! kubectl get kustomization -n flux-system tier-1-infrastructure \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; do
  check_timeout
  echo "  ⏳ Tier 1 not ready yet, waiting 10s..."
  sleep 10
done
echo "✅ Tier 1 (Infrastructure) Ready"

# MUST HAVE: Critical apps deployed and ready
echo "Checking critical applications..."

CRITICAL_APPS=(
  "default/plex"
  "default/home-assistant"
  "default/immich"
)

ALL_READY=false
while [ "$ALL_READY" != "true" ]; do
  check_timeout

  FAILED_APPS=()

  for app in "${CRITICAL_APPS[@]}"; do
    NAMESPACE=$(echo "$app" | cut -d'/' -f1)
    NAME=$(echo "$app" | cut -d'/' -f2)

    if kubectl get helmrelease -n "$NAMESPACE" "$NAME" &>/dev/null; then
      if kubectl get helmrelease -n "$NAMESPACE" "$NAME" \
          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        echo "  ✅ $app Ready"
      else
        echo "  ⏳ $app exists but not ready yet"
        FAILED_APPS+=("$app")
      fi
    else
      echo "  ⚠️  $app not found (may not have deployed yet)"
      FAILED_APPS+=("$app")
    fi
  done

  if [ ${#FAILED_APPS[@]} -eq 0 ]; then
    ALL_READY=true
  else
    echo "  Waiting 30s for critical apps: ${FAILED_APPS[*]}"
    sleep 30
  fi
done

ELAPSED=$(($(date +%s) - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

echo ""
echo "✅ Bootstrap complete! All tiers and critical apps Ready."
echo "⏱️  Total time: ${ELAPSED_MIN}m ${ELAPSED_SEC}s"
echo "✅ Safe to switch to steady-state intervals."
exit 0
