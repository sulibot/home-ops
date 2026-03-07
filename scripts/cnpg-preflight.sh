#!/usr/bin/env bash
# cnpg-preflight.sh — fail-fast CNPG backup readiness preflight
#
# Purpose:
# - Run before cluster rebuild apply paths.
# - In RESTORE_REQUIRED mode, verify at least one fresh restore source exists
#   (plugin backup or VolumeSnapshot), and report both ages.
#
# Env:
#   CNPG_RESTORE_MODE=RESTORE_REQUIRED|NEW_DB
#   CNPG_NEW_DB=true|false (legacy alias if CNPG_RESTORE_MODE not set)
#   CNPG_BACKUP_MAX_AGE_HOURS=36
#   CNPG_CLUSTER_NAME=postgres-vectorchord
#   CNPG_CLUSTER_NAMESPACE=default
#   KUBECONFIG=/path
#
# Args:
#   --kubeconfig <path>
#   --cluster <name>
#   --namespace <namespace>

set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
CNPG_RESTORE_MODE_RAW="${CNPG_RESTORE_MODE:-}"
CNPG_NEW_DB_MODE_RAW="${CNPG_NEW_DB:-false}"
CNPG_BACKUP_MAX_AGE_HOURS_RAW="${CNPG_BACKUP_MAX_AGE_HOURS:-36}"
CLUSTER_NAME="${CNPG_CLUSTER_NAME:-postgres-vectorchord}"
CLUSTER_NS="${CNPG_CLUSTER_NAMESPACE:-default}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig)
      KUBECONFIG_PATH="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --namespace)
      CLUSTER_NS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[err] missing required command: $1" >&2
    exit 1
  }
}

require_positive_int() {
  local value="$1"
  local name="$2"
  if ! echo "$value" | grep -Eq '^[0-9]+$' || [ "$value" -le 0 ]; then
    echo "[err] invalid $name='$value' (must be positive integer)" >&2
    exit 1
  fi
}

normalize_mode() {
  local m
  if [ -n "$CNPG_RESTORE_MODE_RAW" ]; then
    m="$(echo "$CNPG_RESTORE_MODE_RAW" | tr '[:lower:]' '[:upper:]' | xargs)"
  else
    if [ "$(echo "$CNPG_NEW_DB_MODE_RAW" | tr '[:upper:]' '[:lower:]' | xargs)" = "true" ]; then
      m="NEW_DB"
    else
      m="RESTORE_REQUIRED"
    fi
  fi

  case "$m" in
    RESTORE_REQUIRED|NEW_DB) echo "$m" ;;
    *)
      echo "[err] invalid CNPG_RESTORE_MODE='$CNPG_RESTORE_MODE_RAW' (expected RESTORE_REQUIRED|NEW_DB)" >&2
      exit 1
      ;;
  esac
}

format_age_human() {
  local seconds="$1"
  if [ -z "$seconds" ] || [ "$seconds" = "null" ]; then
    echo "n/a"
    return
  fi
  local h=$((seconds / 3600))
  local m=$(((seconds % 3600) / 60))
  echo "${h}h${m}m"
}

plugin_backup_age_seconds() {
  kubectl --kubeconfig="$KUBECONFIG_PATH" -n "$CLUSTER_NS" get backup.postgresql.cnpg.io -o json 2>/dev/null | \
    jq -r '
      [ .items[]?
        | select(
            ((.metadata.labels["cnpg.io/cluster"] // "") == "'"$CLUSTER_NAME"'")
            or ((.spec.cluster.name // "") == "'"$CLUSTER_NAME"'")
          )
        | select((.spec.method // "") == "plugin")
        | select((.status.phase // "" | ascii_downcase) == "completed")
        | (now - ((.status.stoppedAt // .status.completedAt // .metadata.creationTimestamp) | fromdateiso8601))
      ]
      | if length == 0 then "" else (min | floor | tostring) end' 2>/dev/null || true
}

snapshot_age_seconds() {
  kubectl --kubeconfig="$KUBECONFIG_PATH" -n "$CLUSTER_NS" get volumesnapshots.snapshot.storage.k8s.io -l "cnpg.io/cluster=${CLUSTER_NAME}" -o json 2>/dev/null | \
    jq -r '
      [ .items[]?
        | select((.status.readyToUse // false) == true)
        | (now - (.metadata.creationTimestamp | fromdateiso8601))
      ]
      | if length == 0 then "" else (min | floor | tostring) end' 2>/dev/null || true
}

require_cmd kubectl
require_cmd jq
require_positive_int "$CNPG_BACKUP_MAX_AGE_HOURS_RAW" "CNPG_BACKUP_MAX_AGE_HOURS"

MODE="$(normalize_mode)"
MAX_AGE_SECONDS="$(( CNPG_BACKUP_MAX_AGE_HOURS_RAW * 3600 ))"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CNPG PRE-FLIGHT BACKUP CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Mode: $MODE"
echo "Cluster: ${CLUSTER_NS}/${CLUSTER_NAME}"
echo "Freshness threshold: ${CNPG_BACKUP_MAX_AGE_HOURS_RAW}h"

if [ "$MODE" = "NEW_DB" ]; then
  echo "[ok] NEW_DB mode set, skipping restore-source freshness gate"
  exit 0
fi

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "[err] kubeconfig not found at $KUBECONFIG_PATH" >&2
  echo "[err] restore-required mode needs a running source cluster to verify backups before rebuild" >&2
  exit 1
fi

if ! kubectl --kubeconfig="$KUBECONFIG_PATH" version --request-timeout=10s >/dev/null 2>&1; then
  echo "[err] cannot reach Kubernetes API using kubeconfig: $KUBECONFIG_PATH" >&2
  echo "[err] restore-required mode needs source cluster connectivity for backup preflight" >&2
  exit 1
fi

plugin_age="$(plugin_backup_age_seconds)"
snap_age="$(snapshot_age_seconds)"

if [ -n "$plugin_age" ]; then
  echo "plugin backup age: $(format_age_human "$plugin_age")"
else
  echo "plugin backup age: none found"
fi

if [ -n "$snap_age" ]; then
  echo "snapshot age: $(format_age_human "$snap_age")"
else
  echo "snapshot age: none found"
fi

plugin_fresh="false"
snap_fresh="false"

if [ -n "$plugin_age" ] && [ "$plugin_age" -le "$MAX_AGE_SECONDS" ]; then
  plugin_fresh="true"
fi
if [ -n "$snap_age" ] && [ "$snap_age" -le "$MAX_AGE_SECONDS" ]; then
  snap_fresh="true"
fi

if [ "$plugin_fresh" = "true" ] || [ "$snap_fresh" = "true" ]; then
  echo "[ok] restore preflight passed (at least one fresh source available)"
  exit 0
fi

echo "[err] no fresh restore sources found (plugin backup and snapshot are stale/missing)" >&2
echo "[err] refusing rebuild in RESTORE_REQUIRED mode" >&2
echo "[err] options: refresh backup, or explicitly set CNPG_RESTORE_MODE=NEW_DB" >&2
exit 1
