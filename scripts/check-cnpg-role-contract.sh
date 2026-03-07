#!/usr/bin/env bash
# Validate CNPG Database owner contract:
# - every Database.spec.owner must exist in Cluster.spec.managed.roles
# - each owner role must define passwordSecret.name == <owner>-pg-password

set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[err] missing required command: $1" >&2
    exit 1
  }
}

norm() {
  local v="$1"
  if [ "$v" = "null" ]; then
    echo ""
  else
    echo "$v"
  fi
}

require_cmd yq

APP_ROOT="kubernetes/apps/tier-1-infrastructure/postgres-vectorchord"
DB_DIR="${APP_ROOT}/databases"
SPEC_FILES=(
  "${APP_ROOT}/app/cluster.yaml"
  "${APP_ROOT}/app-false/cluster.yaml"
  "${APP_ROOT}/app-true/cluster.yaml"
)

for f in "${SPEC_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "[err] missing cluster spec file: $f" >&2
    exit 1
  fi
done

if [ ! -d "$DB_DIR" ]; then
  echo "[err] missing databases directory: $DB_DIR" >&2
  exit 1
fi

mapfile -t owners < <(
  yq eval '.spec.owner // ""' "${DB_DIR}"/*.yaml | \
    sed '/^$/d;/^---$/d' | sort -u
)

if [ "${#owners[@]}" -eq 0 ]; then
  echo "[err] no database owners discovered under ${DB_DIR}" >&2
  exit 1
fi

echo "Checking CNPG owner-role contract for owners: ${owners[*]}"

errors=0
for spec in "${SPEC_FILES[@]}"; do
  echo "  validating: ${spec}"
  for owner in "${owners[@]}"; do
    role_name="$(norm "$(yq eval ".spec.managed.roles[] | select(.name == \"${owner}\") | .name" "$spec" 2>/dev/null | head -n1)")"
    secret_name="$(norm "$(yq eval ".spec.managed.roles[] | select(.name == \"${owner}\") | .passwordSecret.name // \"\"" "$spec" 2>/dev/null | head -n1)")"
    expected_secret="${owner}-pg-password"

    if [ -z "$role_name" ]; then
      echo "[err] ${spec}: missing managed role for owner '${owner}'" >&2
      errors=$((errors + 1))
      continue
    fi

    if [ "$secret_name" != "$expected_secret" ]; then
      echo "[err] ${spec}: role '${owner}' has passwordSecret='${secret_name:-<empty>}' expected='${expected_secret}'" >&2
      errors=$((errors + 1))
    fi
  done
done

if [ "$errors" -gt 0 ]; then
  echo "[err] CNPG owner-role contract check failed with ${errors} error(s)" >&2
  exit 1
fi

echo "[ok] CNPG owner-role contract check passed"
