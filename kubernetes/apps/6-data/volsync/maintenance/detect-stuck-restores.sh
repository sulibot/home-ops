#!/usr/bin/env bash
#
# Detect stuck Volsync ReplicationDestination resources
#
# A restore is considered "stuck" if:
# 1. It has the manual trigger set to "restore-once"
# 2. The Synchronizing condition is True (actively restoring)
# 3. It has been in this state for longer than STUCK_THRESHOLD_MINUTES
#
# This typically happens when:
# - The mover job hangs or fails silently
# - Network issues prevent Kopia from accessing the repository
# - The PVC being restored to has permission issues

set -euo pipefail

# Configuration
STUCK_THRESHOLD_MINUTES="${STUCK_THRESHOLD_MINUTES:-60}"  # Default: 60 minutes
DRY_RUN="${DRY_RUN:-true}"  # Default: only detect, don't fix

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🔍 Scanning for stuck ReplicationDestination resources..."
echo "   Threshold: ${STUCK_THRESHOLD_MINUTES} minutes"
echo ""

# Get current time in seconds since epoch
CURRENT_TIME=$(date +%s)
STUCK_COUNT=0

# Find all ReplicationDestinations with manual trigger set to restore-once
kubectl get replicationdestination -A -o json | jq -r '.items[] |
  select(.spec.trigger.manual == "restore-once") |
  select(.status.conditions[]? | select(.type == "Synchronizing" and .status == "True")) |
  "\(.metadata.namespace)|\(.metadata.name)|\(.status.conditions[] | select(.type == "Synchronizing") | .lastTransitionTime)"
' | while IFS='|' read -r namespace name transition_time; do

  # Convert transition time to seconds since epoch
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    TRANSITION_SECONDS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$transition_time" +%s 2>/dev/null || echo 0)
  else
    # Linux
    TRANSITION_SECONDS=$(date -d "$transition_time" +%s 2>/dev/null || echo 0)
  fi

  if [ "$TRANSITION_SECONDS" -eq 0 ]; then
    echo "${YELLOW}⚠️  Could not parse timestamp for ${namespace}/${name}${NC}"
    continue
  fi

  # Calculate how long it's been stuck (in minutes)
  STUCK_DURATION_SECONDS=$((CURRENT_TIME - TRANSITION_SECONDS))
  STUCK_DURATION_MINUTES=$((STUCK_DURATION_SECONDS / 60))

  if [ "$STUCK_DURATION_MINUTES" -gt "$STUCK_THRESHOLD_MINUTES" ]; then
    STUCK_COUNT=$((STUCK_COUNT + 1))

    echo "${RED}🚨 STUCK: ${namespace}/${name}${NC}"
    echo "   Duration: ${STUCK_DURATION_MINUTES} minutes (threshold: ${STUCK_THRESHOLD_MINUTES})"
    echo "   Started: ${transition_time}"

    # Get more details about the stuck restore
    echo ""
    echo "   📋 Status Details:"
    kubectl get replicationdestination -n "$namespace" "$name" -o json | jq -r '
      "   Last Sync Time: \(.status.lastSyncTime // "N/A")",
      "   Last Sync Duration: \(.status.lastSyncDuration // "N/A")",
      "   Latest Mover Status: \(.status.latestMoverStatus.result // "N/A")"
    '

    # Check if mover job exists
    echo ""
    echo "   🔧 Checking mover jobs:"
    MOVER_JOBS=$(kubectl get jobs -n "$namespace" -l "volsync.backube/replication-destination=${name}" --sort-by=.metadata.creationTimestamp -o name | tail -3)

    if [ -z "$MOVER_JOBS" ]; then
      echo "      ${YELLOW}No mover jobs found${NC}"
    else
      echo "$MOVER_JOBS" | while read -r job; do
        JOB_NAME=$(basename "$job")
        JOB_STATUS=$(kubectl get job -n "$namespace" "$JOB_NAME" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status},{.status.conditions[?(@.type=="Failed")].status},{.status.active}')
        echo "      - $JOB_NAME: $JOB_STATUS"
      done
    fi

    echo ""
    echo "   💡 Suggested Actions:"
    echo "      1. Check mover job logs: kubectl logs -n $namespace -l volsync.backube/replication-destination=$name"
    echo "      2. Check Kopia repository connectivity"
    echo "      3. Delete stuck mover job: kubectl delete jobs -n $namespace -l volsync.backube/replication-destination=$name"
    echo "      4. Reset trigger: kubectl patch replicationdestination -n $namespace $name --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/trigger/manual\",\"value\":\"restore-again\"}]'"

    if [ "$DRY_RUN" = "false" ]; then
      echo ""
      echo "${YELLOW}   🔄 AUTO-FIX: Deleting stuck mover jobs and resetting trigger...${NC}"

      # Delete stuck mover jobs
      kubectl delete jobs -n "$namespace" -l "volsync.backube/replication-destination=${name}" --ignore-not-found=true

      # Reset the trigger to force a new restore
      kubectl patch replicationdestination -n "$namespace" "$name" --type=json \
        -p '[{"op":"replace","path":"/spec/trigger/manual","value":"restore-again"}]'

      echo "${GREEN}   ✅ Fixed: ${namespace}/${name}${NC}"
    fi

    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo ""
  fi
done

echo ""
if [ "$STUCK_COUNT" -eq 0 ]; then
  echo "${GREEN}✅ No stuck restores detected${NC}"
else
  echo "${RED}Found ${STUCK_COUNT} stuck restore(s)${NC}"

  if [ "$DRY_RUN" = "true" ]; then
    echo ""
    echo "${YELLOW}ℹ️  This was a dry run. To automatically fix stuck restores, run:${NC}"
    echo "   DRY_RUN=false $0"
  fi
fi

exit $STUCK_COUNT
