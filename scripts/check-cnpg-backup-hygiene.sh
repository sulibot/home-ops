#!/usr/bin/env bash
# Validate every repository-owned CNPG ScheduledBackup/ObjectStore label rather
# than silently protecting only the original household PostgreSQL cluster.

set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[err] missing required command: $1" >&2
    exit 1
  }
}

require_cmd yq
require_cmd rg

ROOT="kubernetes/apps"
mapfile -t cluster_specs < <(rg -l '^kind: Cluster$' "$ROOT" --glob '*.yaml' | sort)
mapfile -t backup_specs < <(rg -l '^kind: (ObjectStore|ScheduledBackup)$' "$ROOT" --glob '*.yaml' | sort)
mapfile -t known_clusters < <(
  for file in "${cluster_specs[@]}"; do
    yq eval 'select(.apiVersion == "postgresql.cnpg.io/v1" and .kind == "Cluster") | .metadata.name // ""' "$file"
  done | sed '/^$/d;/^---$/d' | sort -u
)

is_known_cluster() {
  local candidate="$1"
  local cluster
  for cluster in "${known_clusters[@]}"; do
    [[ "$cluster" == "$candidate" ]] && return 0
  done
  return 1
}

errors=0
resource_count=0
for file in "${backup_specs[@]}"; do
  while IFS=$'\t' read -r kind label cluster_ref; do
    [[ -n "$kind" ]] || continue
    resource_count=$((resource_count + 1))

    if [[ -z "$label" ]]; then
      echo "[err] ${file}: ${kind} is missing metadata.labels.cnpg.io/cluster" >&2
      errors=$((errors + 1))
      continue
    fi
    if ! is_known_cluster "$label"; then
      echo "[err] ${file}: ${kind} labels unknown Cluster '${label}'" >&2
      errors=$((errors + 1))
    fi
    if [[ "$kind" == "ScheduledBackup" && "$cluster_ref" != "$label" ]]; then
      echo "[err] ${file}: ScheduledBackup label '${label}' does not match spec.cluster.name '${cluster_ref:-<empty>}'" >&2
      errors=$((errors + 1))
    fi
  done < <(
    yq eval -o=tsv \
      'select(.kind == "ObjectStore" or .kind == "ScheduledBackup") | [.kind, (.metadata.labels."cnpg.io/cluster" // ""), (.spec.cluster.name // "")]' \
      "$file" | sed '/^---$/d'
  )
done

if [[ "$resource_count" -eq 0 ]]; then
  echo "[err] no CNPG backup resources discovered under ${ROOT}" >&2
  exit 1
fi

if [[ "$errors" -gt 0 ]]; then
  echo "[err] CNPG backup hygiene check failed with ${errors} error(s)" >&2
  exit 1
fi

echo "[ok] CNPG backup hygiene passed for ${resource_count} resource(s) across ${#known_clusters[@]} Cluster name(s)"
