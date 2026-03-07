#!/usr/bin/env bash
# cnpg-restore.sh — deterministic CNPG restore orchestration for postgres-vectorchord
#
# Modes:
#   RESTORE_REQUIRED (default): require fresh backup source; fail if none exists.
#   NEW_DB: allow fresh DB bootstrap if no fresh backup source exists.
#
# Env:
#   CNPG_RESTORE_MODE=RESTORE_REQUIRED|NEW_DB
#   CNPG_NEW_DB=true|false (legacy alias; ignored when CNPG_RESTORE_MODE is set)
#   CNPG_RESTORE_METHOD=auto|barman|snapshot (default: auto)
#   CNPG_BACKUP_MAX_AGE_HOURS=36
#   CNPG_STORAGE_SIZE=60Gi
#   CNPG_STALE_BACKUP_MAX_AGE_MINUTES=45
#   CNPG_CLUSTER_NAME=postgres-vectorchord
#   CNPG_CLUSTER_NAMESPACE=default
#   CNPG_KUSTOMIZATION_NAMESPACE=flux-system
#   CNPG_KUSTOMIZATION_NAME=postgres-vectorchord
#   KUBECONFIG=/path

set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
CNPG_RESTORE_MODE_RAW="${CNPG_RESTORE_MODE:-}"
CNPG_NEW_DB_MODE_RAW="${CNPG_NEW_DB:-false}"
CNPG_RESTORE_METHOD_RAW="${CNPG_RESTORE_METHOD:-auto}"
CNPG_BACKUP_MAX_AGE_HOURS_RAW="${CNPG_BACKUP_MAX_AGE_HOURS:-36}"
CNPG_STALE_BACKUP_MAX_AGE_MINUTES_RAW="${CNPG_STALE_BACKUP_MAX_AGE_MINUTES:-45}"
CNPG_STORAGE_SIZE="${CNPG_STORAGE_SIZE:-60Gi}"

CLUSTER_NAME="${CNPG_CLUSTER_NAME:-postgres-vectorchord}"
CLUSTER_NS="${CNPG_CLUSTER_NAMESPACE:-default}"
KUSTOMIZATION_NS="${CNPG_KUSTOMIZATION_NAMESPACE:-flux-system}"
KUSTOMIZATION_NAME="${CNPG_KUSTOMIZATION_NAME:-postgres-vectorchord}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig)
      KUBECONFIG_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--kubeconfig <path>]" >&2
      exit 1
      ;;
  esac
done

KC="kubectl --kubeconfig=$KUBECONFIG_PATH"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Missing required command: $1"
    exit 1
  }
}

log() { echo "$*"; }
warn() { echo "[warn] $*"; }
err() { echo "[err] $*"; }

require_positive_int() {
  local value="$1"
  local name="$2"
  if ! echo "$value" | grep -Eq '^[0-9]+$' || [ "$value" -le 0 ]; then
    err "Invalid $name='$value' (must be positive integer)"
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
      err "Invalid CNPG_RESTORE_MODE='$CNPG_RESTORE_MODE_RAW' (expected RESTORE_REQUIRED|NEW_DB)"
      exit 1
      ;;
  esac
}

normalize_restore_method() {
  local method
  method="$(echo "$CNPG_RESTORE_METHOD_RAW" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "$method" in
    auto|barman|snapshot) echo "$method" ;;
    *)
      err "Invalid CNPG_RESTORE_METHOD='$CNPG_RESTORE_METHOD_RAW' (expected auto|barman|snapshot)"
      exit 1
      ;;
  esac
}

require_positive_int "$CNPG_BACKUP_MAX_AGE_HOURS_RAW" "CNPG_BACKUP_MAX_AGE_HOURS"
require_positive_int "$CNPG_STALE_BACKUP_MAX_AGE_MINUTES_RAW" "CNPG_STALE_BACKUP_MAX_AGE_MINUTES"

MODE="$(normalize_mode)"
RESTORE_METHOD_PREF="$(normalize_restore_method)"
BACKUP_MAX_AGE_SECONDS="$(( CNPG_BACKUP_MAX_AGE_HOURS_RAW * 3600 ))"
STALE_BACKUP_MAX_AGE_SECONDS="$(( CNPG_STALE_BACKUP_MAX_AGE_MINUTES_RAW * 60 ))"

require_cmd kubectl
require_cmd jq

SCHEDULEDBACKUP_PREV_STATES=()
RESUME_FLUX_ON_EXIT="false"

cleanup_on_exit() {
  if [ "$RESUME_FLUX_ON_EXIT" = "true" ]; then
    log "Restoring Flux kustomization suspend=false..."
    $KC -n "$KUSTOMIZATION_NS" patch kustomization "$KUSTOMIZATION_NAME" --type=merge -p '{"spec":{"suspend":false}}' >/dev/null 2>&1 || true
  fi

  if [ "${#SCHEDULEDBACKUP_PREV_STATES[@]}" -gt 0 ]; then
    log "Restoring ScheduledBackup suspend states..."
    for row in "${SCHEDULEDBACKUP_PREV_STATES[@]}"; do
      name="${row%%:*}"
      prev="${row#*:}"
      [ -n "$name" ] || continue
      if [ "$prev" = "true" ]; then
        $KC -n "$CLUSTER_NS" patch scheduledbackup "$name" --type=merge -p '{"spec":{"suspend":true}}' >/dev/null 2>&1 || true
      else
        $KC -n "$CLUSTER_NS" patch scheduledbackup "$name" --type=merge -p '{"spec":{"suspend":false}}' >/dev/null 2>&1 || true
      fi
    done
  fi
}
trap cleanup_on_exit EXIT

wait_for_crd() {
  local crd="$1"
  local timeout="$2"
  $KC wait --for=condition=Established "crd/${crd}" --timeout="$timeout" >/dev/null
}

wait_for_deployment_by_label() {
  local ns="$1"
  local label="$2"
  local timeout="$3"
  $KC -n "$ns" wait deployment -l "$label" --for=condition=Available --timeout="$timeout" >/dev/null
}

cluster_phase() {
  $KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true
}

wait_for_cluster_healthy() {
  local timeout_seconds="$1"
  local i=0
  local loops=$(( timeout_seconds / 10 ))

  while [ "$i" -lt "$loops" ]; do
    local phase
    phase="$(cluster_phase)"
    log "      [$((i+1))/$loops] Phase: ${phase:-Pending}"
    if echo "$phase" | grep -qi "healthy"; then
      return 0
    fi
    sleep 10
    i=$((i+1))
  done

  return 1
}

wait_for_primary_pod() {
  local timeout_seconds="$1"
  local i=0
  local loops=$(( timeout_seconds / 5 ))
  while [ "$i" -lt "$loops" ]; do
    local p
    p="$($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
    if [ -n "$p" ]; then
      echo "$p"
      return 0
    fi
    sleep 5
    i=$((i+1))
  done
  return 1
}

run_psql() {
  local pod="$1"
  local sql="$2"
  $KC -n "$CLUSTER_NS" exec "$pod" -- psql -U postgres -Atqc "$sql"
}

wait_for_secrets() {
  local timeout_seconds="$1"
  shift
  local secrets=("$@")
  local i=0
  local loops=$(( timeout_seconds / 5 ))

  while [ "$i" -lt "$loops" ]; do
    local missing=0
    for s in "${secrets[@]}"; do
      if ! $KC -n "$CLUSTER_NS" get secret "$s" >/dev/null 2>&1; then
        missing=$((missing + 1))
      fi
    done

    if [ "$missing" -eq 0 ]; then
      return 0
    fi

    sleep 5
    i=$((i+1))
  done

  return 1
}

suspend_flux_kustomization_if_needed() {
  local current
  current="$($KC -n "$KUSTOMIZATION_NS" get kustomization "$KUSTOMIZATION_NAME" -o jsonpath='{.spec.suspend}' 2>/dev/null || true)"

  if [ "$current" = "true" ]; then
    log "Flux kustomization already suspended: ${KUSTOMIZATION_NS}/${KUSTOMIZATION_NAME}"
    RESUME_FLUX_ON_EXIT="false"
    return
  fi

  $KC -n "$KUSTOMIZATION_NS" patch kustomization "$KUSTOMIZATION_NAME" --type=merge -p '{"spec":{"suspend":true}}' >/dev/null
  RESUME_FLUX_ON_EXIT="true"
}

suspend_scheduled_backups() {
  mapfile -t backups < <($KC -n "$CLUSTER_NS" get scheduledbackup -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [ "${#backups[@]}" -eq 0 ]; then
    return 0
  fi

  log "Suspending ScheduledBackups during restore..."
  for b in "${backups[@]}"; do
    if [ -n "$b" ]; then
      local prev
      prev="$($KC -n "$CLUSTER_NS" get scheduledbackup "$b" -o jsonpath='{.spec.suspend}' 2>/dev/null || true)"
      [ -n "$prev" ] || prev="false"
      SCHEDULEDBACKUP_PREV_STATES+=("${b}:${prev}")
      if [ "$prev" != "true" ]; then
        $KC -n "$CLUSTER_NS" patch scheduledbackup "$b" --type=merge -p '{"spec":{"suspend":true}}' >/dev/null || true
      fi
    fi
  done
}

clear_stale_noncompleted_backup_crs() {
  local stale_cutoff="$STALE_BACKUP_MAX_AGE_SECONDS"
  mapfile -t stale_names < <(
    $KC -n "$CLUSTER_NS" get backup.postgresql.cnpg.io -o json 2>/dev/null | \
      jq -r --argjson cutoff "$stale_cutoff" --arg cluster "$CLUSTER_NAME" '
        [.items[]?
          | select(
              ((.metadata.labels["cnpg.io/cluster"] // "") == $cluster)
              or ((.spec.cluster.name // "") == $cluster)
            )
          | select((.status.phase // "" | ascii_downcase) != "completed")
          | {name: .metadata.name, ts: (.status.startedAt // .metadata.creationTimestamp // "")}
          | select(.ts != "")
          | . + {age: (now - (.ts | fromdateiso8601))}
          | select(.age > $cutoff)
          | .name
        ] | .[]'
  )

  if [ "${#stale_names[@]}" -eq 0 ]; then
    return 0
  fi

  warn "Deleting stale non-completed Backup CRs: ${stale_names[*]}"
  for b in "${stale_names[@]}"; do
    $KC -n "$CLUSTER_NS" delete backup.postgresql.cnpg.io "$b" --ignore-not-found >/dev/null 2>&1 || true
  done
}

newest_completed_backup_age_seconds() {
  local method="$1"
  local out
  out="$(
    $KC -n "$CLUSTER_NS" get backup.postgresql.cnpg.io -o json 2>/dev/null | \
      jq -r --arg method "$method" --arg cluster "$CLUSTER_NAME" '
        [ .items[]?
          | select(
              ((.metadata.labels["cnpg.io/cluster"] // "") == $cluster)
              or ((.spec.cluster.name // "") == $cluster)
            )
          | select((.spec.method // "") == $method)
          | select((.status.phase // "" | ascii_downcase) == "completed")
          | (now - ((.status.stoppedAt // .status.completedAt // .metadata.creationTimestamp) | fromdateiso8601))
        ]
        | if length == 0 then "" else (min | floor | tostring) end' 2>/dev/null || true
  )"
  echo "$out"
}

newest_snapshot_age_seconds() {
  local out
  out="$(
    $KC -n "$CLUSTER_NS" get volumesnapshots.snapshot.storage.k8s.io -l "cnpg.io/cluster=${CLUSTER_NAME}" -o json 2>/dev/null | \
      jq -r '
        [ .items[]?
          | select((.status.readyToUse // false) == true)
          | (now - (.metadata.creationTimestamp | fromdateiso8601))
        ]
        | if length == 0 then "" else (min | floor | tostring) end' 2>/dev/null || true
  )"
  echo "$out"
}

format_age_human() {
  local seconds="$1"
  if [ -z "$seconds" ]; then
    echo "n/a"
    return
  fi
  local h=$((seconds / 3600))
  local m=$(((seconds % 3600) / 60))
  echo "${h}h${m}m"
}

RESTORE_METHOD=""
detect_restore_method() {
  local plugin_age snapshot_age
  plugin_age="$(newest_completed_backup_age_seconds "plugin")"
  snapshot_age="$(newest_snapshot_age_seconds)"

  if [ -n "$plugin_age" ]; then
    log "  plugin backup age: $(format_age_human "$plugin_age")"
  else
    warn "No completed plugin backups found"
  fi

  if [ -n "$snapshot_age" ]; then
    log "  snapshot age: $(format_age_human "$snapshot_age")"
  else
    warn "No ready snapshots found"
  fi

  local plugin_fresh="false"
  local snapshot_fresh="false"
  if [ -n "$plugin_age" ] && [ "$plugin_age" -le "$BACKUP_MAX_AGE_SECONDS" ]; then
    plugin_fresh="true"
  fi
  if [ -n "$snapshot_age" ] && [ "$snapshot_age" -le "$BACKUP_MAX_AGE_SECONDS" ]; then
    snapshot_fresh="true"
  fi

  if [ "$RESTORE_METHOD_PREF" = "barman" ]; then
    if [ "$plugin_fresh" = "true" ]; then
      RESTORE_METHOD="barman"
    fi
    return
  fi

  if [ "$RESTORE_METHOD_PREF" = "snapshot" ]; then
    if [ "$snapshot_fresh" = "true" ]; then
      RESTORE_METHOD="snapshot"
    fi
    return
  fi

  # auto preference: barman first, snapshot fallback.
  if [ "$plugin_fresh" = "true" ]; then
    RESTORE_METHOD="barman"
    return
  fi
  if [ "$snapshot_fresh" = "true" ]; then
    RESTORE_METHOD="snapshot"
    return
  fi
}

patch_missing_roles_from_database_owners() {
  local primary="$1"
  local dbjson
  dbjson="$($KC -n "$CLUSTER_NS" get databases.postgresql.cnpg.io -o json 2>/dev/null || echo '{"items":[]}')"

  mapfile -t owners < <(echo "$dbjson" | jq -r '.items[].spec.owner // empty' | sort -u)
  if [ "${#owners[@]}" -eq 0 ]; then
    return 0
  fi

  mapfile -t existing < <($KC -n "$CLUSTER_NS" get cluster "$CLUSTER_NAME" -o json | jq -r '.spec.managed.roles[]?.name')

  for o in "${owners[@]}"; do
    if ! printf '%s\n' "${existing[@]}" | grep -qx "$o"; then
      warn "Adding missing CNPG managed role for database owner: $o"
      $KC -n "$CLUSTER_NS" patch cluster "$CLUSTER_NAME" --type=json \
        -p="[{\"op\":\"add\",\"path\":\"/spec/managed/roles/-\",\"value\":{\"name\":\"$o\",\"login\":true,\"ensure\":\"present\"}}]" >/dev/null
    fi

    if ! run_psql "$primary" "SELECT 1 FROM pg_roles WHERE rolname='$o';" 2>/dev/null | grep -qx 1; then
      warn "Role '$o' not visible in PostgreSQL yet; CNPG will reconcile shortly"
    fi
  done
}

wait_for_databases_applied() {
  local timeout_seconds="$1"
  local i=0
  local loops=$(( timeout_seconds / 10 ))

  while [ "$i" -lt "$loops" ]; do
    local pending
    pending="$($KC -n "$CLUSTER_NS" get databases.postgresql.cnpg.io -o json 2>/dev/null | \
      jq -r '[.items[] | select((.status.applied // false) != true) | .metadata.name] | join(",")' || true)"

    if [ -z "$pending" ] || [ "$pending" = "null" ]; then
      return 0
    fi

    warn "Waiting for Database CRs to apply: $pending"
    sleep 10
    i=$((i+1))
  done

  return 1
}

log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "CNPG AUTOMATIC RESTORE CHECK"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Mode: $MODE"
log "Restore method preference: $RESTORE_METHOD_PREF"
log "Fresh backup max age: ${CNPG_BACKUP_MAX_AGE_HOURS_RAW}h"

log "Waiting for CNPG CRD registration (up to 10m)..."
if ! wait_for_crd "clusters.postgresql.cnpg.io" "600s"; then
  warn "CNPG CRDs not available after 10m — skipping restore check"
  exit 0
fi

OPERATOR_NS="$($KC get deployment -A -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
if [ -z "$OPERATOR_NS" ]; then
  warn "CNPG operator deployment not found — skipping restore check"
  exit 0
fi
log "  operator namespace: $OPERATOR_NS"
if ! wait_for_deployment_by_label "$OPERATOR_NS" "app.kubernetes.io/name=cloudnative-pg" "300s"; then
  warn "CNPG operator not ready after 5m — skipping restore check"
  exit 0
fi
log "  CNPG operator ready"

if [ "$(cluster_phase)" = "Cluster in healthy state" ]; then
  primary="$(wait_for_primary_pod 120 || true)"
  if [ -n "$primary" ]; then
    row_count="$(run_psql "$primary" "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';" 2>/dev/null | tr -d ' ' || echo 0)"
    if [ "${row_count:-0}" -gt 0 ] 2>/dev/null; then
      log "  Cluster already healthy with data — skipping restore"
      log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      exit 0
    fi
  fi
fi

detect_restore_method
restore_method="$RESTORE_METHOD"

if [ -z "$restore_method" ]; then
  if [ "$MODE" = "NEW_DB" ]; then
    log "  No fresh backups found — NEW_DB mode allows fresh bootstrap"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
  fi

  err "No fresh backups found and mode is RESTORE_REQUIRED"
  err "Set CNPG_RESTORE_MODE=NEW_DB only when fresh DB bootstrap is intentional"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

log ""
log "  Performing automatic restore via: $restore_method"
log ""

log "  1/8 Suspending Flux kustomization and ScheduledBackups..."
suspend_flux_kustomization_if_needed
suspend_scheduled_backups
clear_stale_noncompleted_backup_crs

log "  2/8 Waiting for required secrets..."
if ! wait_for_secrets 300 \
  "cnpg-barman-s3" \
  "atuin-pg-password" \
  "authentik-pg-password" \
  "firefly-pg-password" \
  "paperless-pg-password"; then
  err "Required CNPG secrets did not appear in 5m"
  exit 1
fi

log "  3/8 Deleting existing CNPG Cluster and stale data PVC (if present)..."
$KC -n "$CLUSTER_NS" delete cluster "$CLUSTER_NAME" --ignore-not-found --wait=true >/dev/null || true
$KC -n "$CLUSTER_NS" delete pvc "${CLUSTER_NAME}-1" --ignore-not-found --wait=true >/dev/null || true

log "  4/8 Applying recovery cluster spec..."
if [ "$restore_method" = "barman" ]; then
  $KC -n "$CLUSTER_NS" apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${CLUSTER_NS}
  annotations:
    cnpg.io/skipEmptyWalArchiveCheck: "enabled"
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.4.3
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  backup:
    volumeSnapshot:
      className: csi-rbd-rbd-vm-snapclass
      snapshotOwnerReference: backup
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: postgres-vectorchord-backup
  bootstrap:
    recovery:
      source: postgres-vectorchord
      database: immich
      owner: immich
  externalClusters:
    - name: postgres-vectorchord
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: postgres-vectorchord-backup
  managed:
    roles:
      - name: atuin
        login: true
        ensure: present
        passwordSecret:
          name: atuin-pg-password
      - name: authentik
        login: true
        ensure: present
        passwordSecret:
          name: authentik-pg-password
      - name: firefly
        login: true
        ensure: present
        passwordSecret:
          name: firefly-pg-password
      - name: paperless
        login: true
        ensure: present
        passwordSecret:
          name: paperless-pg-password
  storage:
    resizeInUseVolumes: true
    size: ${CNPG_STORAGE_SIZE}
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML
else
  snap_name="$($KC -n "$CLUSTER_NS" get volumesnapshots.snapshot.storage.k8s.io -l "cnpg.io/cluster=${CLUSTER_NAME}" \
    -o json | jq -r '[.items[]? | select((.status.readyToUse // false) == true) | .metadata.name] | last // ""')"
  if [ -z "$snap_name" ]; then
    err "Snapshot restore selected but no ready snapshot found"
    exit 1
  fi

  $KC -n "$CLUSTER_NS" apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${CLUSTER_NS}
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.4.3
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  backup:
    volumeSnapshot:
      className: csi-rbd-rbd-vm-snapclass
      snapshotOwnerReference: backup
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: postgres-vectorchord-backup
  bootstrap:
    recovery:
      database: immich
      owner: immich
      volumeSnapshots:
        storage:
          name: ${snap_name}
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
  managed:
    roles:
      - name: atuin
        login: true
        ensure: present
        passwordSecret:
          name: atuin-pg-password
      - name: authentik
        login: true
        ensure: present
        passwordSecret:
          name: authentik-pg-password
      - name: firefly
        login: true
        ensure: present
        passwordSecret:
          name: firefly-pg-password
      - name: paperless
        login: true
        ensure: present
        passwordSecret:
          name: paperless-pg-password
  storage:
    resizeInUseVolumes: true
    size: ${CNPG_STORAGE_SIZE}
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML
fi

log "  5/8 Waiting for cluster recovery (up to 20m)..."
if ! wait_for_cluster_healthy 1200; then
  err "Recovery did not reach healthy phase in 20m"
  exit 1
fi
log "  Cluster recovered"

log "  6/8 Normalizing bootstrap spec (recovery -> initdb) for Flux parity..."
$KC -n "$CLUSTER_NS" patch cluster "$CLUSTER_NAME" --type=json -p '[
  {"op":"replace","path":"/spec/bootstrap","value":{
    "initdb":{
      "database":"immich",
      "owner":"immich",
      "postInitApplicationSQL":[
        "CREATE EXTENSION IF NOT EXISTS vchord CASCADE;",
        "CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE;"
      ]
    }
  }}
]' >/dev/null

log "  7/8 Verifying database capabilities..."
primary="$(wait_for_primary_pod 300 || true)"
if [ -z "$primary" ]; then
  err "Primary pod not found after recovery"
  exit 1
fi

patch_missing_roles_from_database_owners "$primary"
if ! wait_for_databases_applied 600; then
  err "Database CRs did not all reach applied=true within 10m"
  $KC -n "$CLUSTER_NS" get databases.postgresql.cnpg.io -o wide || true
  exit 1
fi

run_psql "$primary" "BEGIN; CREATE TEMP TABLE __ready_probe(id int); INSERT INTO __ready_probe VALUES (1); ROLLBACK;" >/dev/null

log "  8/8 Resuming Flux kustomization..."
if [ "$RESUME_FLUX_ON_EXIT" = "true" ]; then
  $KC -n "$KUSTOMIZATION_NS" patch kustomization "$KUSTOMIZATION_NAME" --type=merge -p '{"spec":{"suspend":false}}' >/dev/null
  RESUME_FLUX_ON_EXIT="false"
fi

cleanup_on_exit
SCHEDULEDBACKUP_PREV_STATES=()

log ""
log "CNPG RESTORE COMPLETE"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
