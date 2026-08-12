#!/usr/bin/env bash
#
# Sync Plumb's secrets from 1Password into the sops-encrypted terraform vars.
#
#   ./scripts/plumb-secrets.sh --dry-run   # show what would be written
#   ./scripts/plumb-secrets.sh             # write them
#
# The values live in 1Password; sops is a derived copy that terraform reads.
# Copying them by hand is how a wrong value gets in and then takes an hour to
# find, so this does it, and refuses rather than writing a placeholder.
#
# Fill these in 1Password FIRST (Kubernetes vault):
#   Supabase Plumb            credential      <- personal access token
#   Supabase Plumb            organization_id
#
# Everything else is already populated.
set -euo pipefail
cd "$(dirname "$0")/.."

SECRETS="terraform/infra/live/common/secrets.sops.yaml"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if ! op vault get Kubernetes >/dev/null 2>&1; then
  echo "Cannot reach the Kubernetes vault. Run 'op signin' first." >&2
  exit 1
fi

read_field() {
  op item get "$1" --vault Kubernetes --fields "label=$2" --reveal 2>/dev/null || true
}

# key-in-sops : 1Password item : field
MAPPING=(
  "supabase_access_token:Supabase Plumb:credential"
  "supabase_organization_id:Supabase Plumb:organization_id"
  "supabase_plumb_db_password:Supabase Plumb:db_password"
  "plumb_smtp_password:Plumb SMTP:credential"
  "plumb_google_client_id:Plumb Google OAuth:username"
  "plumb_google_client_secret:Plumb Google OAuth:credential"
)

# Not in 1Password because it is not a secret — a literal, kept here so the
# sops file is complete and terraform needs no other source.
LITERALS=(
  "plumb_smtp_sender:no-reply@sulibot.com"
)

declare -a WRITES=()
missing=0

for entry in "${MAPPING[@]}"; do
  key="${entry%%:*}"; rest="${entry#*:}"
  item="${rest%%:*}"; field="${rest#*:}"
  value="$(read_field "$item" "$field")"

  if [[ -z "$value" ]]; then
    echo "MISSING  $key  <- '$item' / $field is empty" >&2
    missing=$((missing + 1))
    continue
  fi
  # A placeholder is worse than an empty value: it applies, and fails somewhere
  # far away from here with an error that does not mention 1Password.
  if [[ "$value" == REPLACE-ME* ]]; then
    echo "PLACEHOLDER  $key  <- '$item' / $field still says REPLACE-ME" >&2
    missing=$((missing + 1))
    continue
  fi

  WRITES+=("$key:$value")
  echo "ok       $key  (${#value} chars from '$item')"
done

for entry in "${LITERALS[@]}"; do
  WRITES+=("${entry%%:*}:${entry#*:}")
  echo "ok       ${entry%%:*}  (literal: ${entry#*:})"
done

if [[ $missing -gt 0 ]]; then
  echo >&2
  echo "$missing value(s) not ready. Fill them in 1Password, then re-run." >&2
  exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "Dry run — nothing written. ${#WRITES[@]} keys would be set in $SECRETS."
  exit 0
fi

for w in "${WRITES[@]}"; do
  key="${w%%:*}"; value="${w#*:}"
  sops set "$SECRETS" "[\"$key\"]" "\"$value\""
done

echo
echo "Wrote ${#WRITES[@]} keys to $SECRETS."
echo "Next: terragrunt apply in terraform/infra/live/services/supabase-plumb"
