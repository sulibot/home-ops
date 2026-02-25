#!/usr/bin/env bash
# cnpg-restore.sh — Automated CNPG PostgreSQL restore for postgres-vectorchord
#
# Checks for available backups and restores from barman-cloud WAL (preferred)
# or VolumeSnapshot (fallback). Safe to run at any time — exits cleanly if
# the cluster is already healthy with data, or if no backups are found.
#
# This script contains the same logic as the flux_bootstrap_monitor Terraform
# module's cnpg_restore null_resource, extracted so it can be run standalone
# without Terraform or the Taskfile.
#
# Usage:
#   ./scripts/cnpg-restore.sh [--kubeconfig <path>]
#
# Options:
#   --kubeconfig <path>   Path to kubeconfig (default: $KUBECONFIG or ~/.kube/config)
#
# Exit codes:
#   0  — success (restored or no-op)
#   1  — fatal error (operator unavailable, apply failed, etc.)

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐘 CNPG AUTOMATIC RESTORE CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Wait for CNPG operator ────────────────────────────────────────────────────
# Must wait for the operator pod to be Ready — not just the CRD to exist —
# because the CNPG validating webhook (which rejects invalid Cluster specs)
# runs in the operator pod.
echo "Waiting for CNPG CRDs (up to 10m)..."
if ! $KC wait --for=condition=Available crd/clusters.postgresql.cnpg.io \
    --timeout=600s 2>/dev/null; then
  echo "  ⚠️  CNPG CRDs not available after 10m — skipping restore check"
  exit 0
fi
echo "Waiting for CNPG operator pod (up to 5m)..."
if ! $KC wait pods -l app.kubernetes.io/name=cloudnative-pg \
    -n cnpg-system --for=condition=Ready --timeout=300s 2>/dev/null; then
  echo "  ⚠️  CNPG operator pod not ready after 5m — skipping restore check"
  exit 0
fi
echo "  ✅ CNPG operator ready"

# ── Check if already healthy with data ───────────────────────────────────────
CLUSTER_PHASE=$($KC get cluster postgres-vectorchord -n default \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [ "$CLUSTER_PHASE" = "Cluster in healthy state" ]; then
  echo "  ✅ Cluster already healthy — checking if data exists in 'immich' db..."
  ROW_COUNT=$($KC exec -n default postgres-vectorchord-1 -- \
    psql -U postgres -d immich -c "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';" \
    -t 2>/dev/null | tr -d ' ' || echo "0")
  if [ "${ROW_COUNT:-0}" -gt "0" ] 2>/dev/null; then
    echo "  ✅ Database has data — skipping restore"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
  fi
  echo "  ℹ️  Cluster healthy but database empty — checking for backups to restore"
fi

# ── Determine restore source ──────────────────────────────────────────────────
RESTORE_METHOD=""

# Prefer barman-cloud WAL (off-cluster MinIO backup)
BARMAN_RECOVERY_POINT=$($KC get objectstore postgres-vectorchord-backup -n default \
  -o jsonpath='{.status.serverRecoveryWindow.postgres-vectorchord.firstRecoverabilityPoint}' \
  2>/dev/null || true)

if [ -n "$BARMAN_RECOVERY_POINT" ]; then
  RESTORE_METHOD="barman"
  echo "  📦 barman-cloud backup available (since: $BARMAN_RECOVERY_POINT)"
fi

# Fall back to VolumeSnapshot (local Ceph, faster but cluster-local)
SNAPSHOT=$($KC get volumesnapshot -n default \
  -l cnpg.io/cluster=postgres-vectorchord \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)

if [ -z "$RESTORE_METHOD" ] && [ -n "$SNAPSHOT" ]; then
  RESTORE_METHOD="snapshot"
  echo "  📸 VolumeSnapshot available: $SNAPSHOT"
fi

if [ -z "$RESTORE_METHOD" ]; then
  echo "  ℹ️  No backups found — fresh install, skipping restore"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

echo ""
echo "  🔄 Performing automatic restore via: $RESTORE_METHOD"
echo ""

# ── 1. Suspend Flux kustomization ─────────────────────────────────────────────
echo "  1/6 Suspending postgres-vectorchord Flux kustomization..."
$KC patch kustomization postgres-vectorchord -n flux-system \
  --type=merge -p '{"spec":{"suspend":true}}'

# ── 2. Delete existing cluster and empty PVC ─────────────────────────────────
echo "  2/6 Deleting existing CNPG Cluster (if present)..."
$KC delete cluster postgres-vectorchord -n default --ignore-not-found --wait=true
$KC delete pvc postgres-vectorchord-1 -n default --ignore-not-found --wait=true

# ── 3. Apply recovery cluster spec ───────────────────────────────────────────
echo "  3/6 Applying recovery cluster spec (method: $RESTORE_METHOD)"

if [ "$RESTORE_METHOD" = "barman" ]; then
  # barman-cloud WAL recovery.
  # - Annotation skips the "Expected empty archive" safety check (archive has prior WALs).
  # - database/owner ensures the app secret points to the correct database.
  # - No plugins.isWALArchiver — Flux re-adds it after recovery via cluster.yaml.
  $KC apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-vectorchord
  namespace: default
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
  bootstrap:
    recovery:
      source: postgres-vectorchord
      database: immich
      owner: immich
  externalClusters:
    - name: postgres-vectorchord
      plugin:
        enabled: true
        isWALArchiver: false
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: postgres-vectorchord-backup
  storage:
    resizeInUseVolumes: true
    size: 20Gi
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML

else
  # VolumeSnapshot recovery (fast local Ceph snapshot).
  $KC apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-vectorchord
  namespace: default
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:17-0.4.3
  startDelay: 30
  stopDelay: 30
  switchoverDelay: 60
  postgresql:
    shared_preload_libraries:
      - "vchord.so"
  bootstrap:
    recovery:
      database: immich
      owner: immich
      volumeSnapshots:
        storage:
          name: $SNAPSHOT
          kind: VolumeSnapshot
          apiGroup: snapshot.storage.k8s.io
  storage:
    resizeInUseVolumes: true
    size: 20Gi
    storageClass: csi-rbd-rbd-vm-sc-retain
YAML
fi

# ── 4. Wait for recovery ──────────────────────────────────────────────────────
echo "  4/6 Waiting for cluster recovery (up to 15m)..."
RECOVERY_OK=0
for i in $(seq 1 90); do
  PHASE=$($KC get cluster postgres-vectorchord -n default \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  echo "      [$i/90] Phase: ${PHASE:-Pending}"
  if echo "$PHASE" | grep -qi "healthy"; then
    echo "  ✅ Cluster recovered successfully"
    RECOVERY_OK=1
    break
  fi
  sleep 10
done

if [ "$RECOVERY_OK" -eq 0 ]; then
  echo "  ⚠️  Recovery timed out after 15m — check cluster manually"
  # Continue anyway: normalize bootstrap and resume Flux so the system
  # isn't left permanently suspended.
fi

# ── 5. Normalize bootstrap spec ───────────────────────────────────────────────
# Replace bootstrap.recovery → bootstrap.initdb BEFORE resuming Flux.
#
# WHY: Flux's dry-run 3-way merge combines server:recovery + git:initdb, which
# produces both methods simultaneously. The CNPG webhook rejects this:
#   "Only one bootstrap method can be specified at a time"
# Normalizing server state to initdb (matching Git) makes the dry-run a no-op.
echo "  5/6 Normalizing bootstrap spec (recovery → initdb) to prevent Flux merge conflict..."
$KC patch cluster postgres-vectorchord -n default --type=json -p '[
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
]' && echo "  ✅ Bootstrap normalized to initdb" \
  || echo "  ⚠️  Bootstrap normalization failed (non-fatal — Flux may need manual reconcile)"

# ── 6. Resume Flux kustomization ─────────────────────────────────────────────
echo "  6/6 Resuming postgres-vectorchord Flux kustomization..."
$KC patch kustomization postgres-vectorchord -n flux-system \
  --type=merge -p '{"spec":{"suspend":false}}'

echo ""
echo "✅ CNPG RESTORE COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
