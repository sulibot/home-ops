#!/usr/bin/env bash
# Validate every repository-owned CNPG Database owner against every manifest
# variant of its referenced Cluster. Login roles must use the repository's
# durable password Secret convention; nologin ownership roles need no password.

set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[err] missing required command: $1" >&2
    exit 1
  }
}

norm() {
  local value="$1"
  if [[ "$value" == "null" ]]; then
    printf ''
  else
    printf '%s' "$value"
  fi
}

require_cmd yq
require_cmd rg

ROOT="kubernetes/apps"
mapfile -t database_specs < <(rg -l '^kind: Database$' "$ROOT" --glob '*.yaml' | sort)
mapfile -t cluster_specs < <(rg -l '^kind: Cluster$' "$ROOT" --glob '*.yaml' | sort)

errors=0
database_count=0
for database_file in "${database_specs[@]}"; do
  while IFS=$'\t' read -r cluster_name owner; do
    [[ -n "$cluster_name" && -n "$owner" ]] || continue
    database_count=$((database_count + 1))
    matches=0

    for cluster_file in "${cluster_specs[@]}"; do
      manifest_cluster="$(norm "$(yq eval 'select(.apiVersion == "postgresql.cnpg.io/v1" and .kind == "Cluster") | .metadata.name // ""' "$cluster_file" | head -n1)")"
      [[ "$manifest_cluster" == "$cluster_name" ]] || continue
      matches=$((matches + 1))

      role_name="$(norm "$(yq eval ".spec.managed.roles[]? | select(.name == \"${owner}\") | .name // \"\"" "$cluster_file" | head -n1)")"
      if [[ -z "$role_name" ]]; then
        echo "[err] ${database_file}: owner '${owner}' is absent from ${cluster_file}" >&2
        errors=$((errors + 1))
        continue
      fi

      login="$(norm "$(yq eval ".spec.managed.roles[]? | select(.name == \"${owner}\") | .login // false" "$cluster_file" | head -n1)")"
      secret_name="$(norm "$(yq eval ".spec.managed.roles[]? | select(.name == \"${owner}\") | .passwordSecret.name // \"\"" "$cluster_file" | head -n1)")"
      if [[ "$login" == "true" ]]; then
        expected_secret="${owner//_/-}-pg-password"
        if [[ "$secret_name" != "$expected_secret" ]]; then
          echo "[err] ${cluster_file}: login owner '${owner}' has passwordSecret='${secret_name:-<empty>}' expected='${expected_secret}'" >&2
          errors=$((errors + 1))
        fi
      elif [[ -n "$secret_name" ]]; then
        echo "[err] ${cluster_file}: nologin owner '${owner}' must not carry a password Secret" >&2
        errors=$((errors + 1))
      fi
    done

    if [[ "$matches" -eq 0 ]]; then
      echo "[err] ${database_file}: no Cluster manifest found for '${cluster_name}'" >&2
      errors=$((errors + 1))
    fi
  done < <(
    yq eval -o=tsv \
      'select(.apiVersion == "postgresql.cnpg.io/v1" and .kind == "Database") | [.spec.cluster.name, .spec.owner]' \
      "$database_file" | sed '/^---$/d'
  )
done

if [[ "$database_count" -eq 0 ]]; then
  echo "[err] no CNPG Database resources discovered under ${ROOT}" >&2
  exit 1
fi

if [[ "$errors" -gt 0 ]]; then
  echo "[err] CNPG owner-role contract check failed with ${errors} error(s)" >&2
  exit 1
fi

echo "[ok] CNPG owner-role contract passed for ${database_count} Database resource(s)"
