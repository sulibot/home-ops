#!/usr/bin/env bash
# Validate CNPG backup hygiene:
# - ScheduledBackup and ObjectStore metadata labels include cnpg.io/cluster
# - label value matches postgres-vectorchord

set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[err] missing required command: $1" >&2
    exit 1
  }
}

require_cmd yq

TARGET_CLUSTER="postgres-vectorchord"
ROOT="kubernetes/apps/tier-1-infrastructure/postgres-vectorchord"
FILES=(
  "${ROOT}/app/objectstore.yaml"
  "${ROOT}/app/scheduledbackup.yaml"
  "${ROOT}/app-false/objectstore.yaml"
  "${ROOT}/app-false/scheduledbackup.yaml"
  "${ROOT}/app-true/objectstore.yaml"
  "${ROOT}/app-true/scheduledbackup.yaml"
)

errors=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "[err] missing file: $f" >&2
    errors=$((errors + 1))
    continue
  fi

  mapfile -t vals < <(yq eval '
    select(.kind == "ObjectStore" or .kind == "ScheduledBackup")
    | .metadata.labels."cnpg.io/cluster" // ""
  ' "$f" | sed '/^---$/d')

  if [ "${#vals[@]}" -eq 0 ]; then
    echo "[err] ${f}: no ObjectStore/ScheduledBackup docs found" >&2
    errors=$((errors + 1))
    continue
  fi

  for v in "${vals[@]}"; do
    if [ -z "$v" ]; then
      echo "[err] ${f}: missing metadata.labels.cnpg.io/cluster" >&2
      errors=$((errors + 1))
    elif [ "$v" != "$TARGET_CLUSTER" ]; then
      echo "[err] ${f}: cnpg.io/cluster='${v}' expected='${TARGET_CLUSTER}'" >&2
      errors=$((errors + 1))
    fi
  done
done

if [ "$errors" -gt 0 ]; then
  echo "[err] CNPG backup hygiene check failed with ${errors} error(s)" >&2
  exit 1
fi

echo "[ok] CNPG backup hygiene check passed"
