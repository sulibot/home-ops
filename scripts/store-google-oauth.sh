#!/usr/bin/env bash
#
# Store Google OAuth client credentials in the 1Password Kubernetes vault.
#
#   ./scripts/store-google-oauth.sh results.md      # from the agent's table
#   ./scripts/store-google-oauth.sh --dry-run results.md
#
# Reads the Markdown table produced by docs/google-oauth-setup-prompt.md:
#
#   | project_id | app_name | client_id | client_secret | status |
#
# Creates or updates one item per app, named "Google OAuth - <app_name>".
# Re-running is safe: an existing item is updated in place rather than
# duplicated, so a partial run can simply be repeated with the full table.
set -euo pipefail

VAULT="Kubernetes"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --vault)   VAULT="$2"; shift 2 ;;
    *)         INPUT="$1"; shift ;;
  esac
done

if [[ -z "${INPUT:-}" || ! -f "$INPUT" ]]; then
  echo "usage: $0 [--dry-run] [--vault NAME] <results.md>" >&2
  exit 1
fi

if ! op vault get "$VAULT" >/dev/null 2>&1; then
  echo "Cannot reach the '$VAULT' vault. Run 'op signin' first." >&2
  exit 1
fi

created=0; updated=0; skipped=0

# Read the pipe table, ignoring the header and separator rows. Fields are
# trimmed because agents pad table cells inconsistently.
while IFS='|' read -r _ project app client_id client_secret status _; do
  project=$(echo "$project" | xargs)
  app=$(echo "$app" | xargs)
  client_id=$(echo "$client_id" | xargs)
  client_secret=$(echo "$client_secret" | xargs)
  status=$(echo "$status" | xargs)

  # Header, separator, and any row the agent flagged as failed.
  [[ "$project" == "project_id" || "$project" =~ ^-*$ || -z "$project" ]] && continue
  if [[ -z "$client_id" || "$client_id" != *apps.googleusercontent.com ]]; then
    echo "skip  $project — no usable client_id (got: ${client_id:-empty})"
    skipped=$((skipped + 1))
    continue
  fi

  title="Google OAuth - ${app}"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "would store  $title  (${project}, ${status})"
    continue
  fi

  if op item get "$title" --vault "$VAULT" >/dev/null 2>&1; then
    op item edit "$title" --vault "$VAULT" \
      "client_id[text]=$client_id" \
      "credential[password]=$client_secret" \
      "project_id[text]=$project" \
      "app_name[text]=$app" \
      "publishing_status[text]=$status" >/dev/null
    echo "updated  $title"
    updated=$((updated + 1))
  else
    # API Credential rather than Login: there is no username, and the secret
    # belongs in a concealed field so it is masked in the UI and needs
    # --reveal to read from the CLI.
    op item create --vault "$VAULT" \
      --category "API Credential" \
      --title "$title" \
      "client_id[text]=$client_id" \
      "credential[password]=$client_secret" \
      "project_id[text]=$project" \
      "app_name[text]=$app" \
      "publishing_status[text]=$status" \
      "redirect_uri[text]=http://127.0.0.1:54321/auth/v1/callback" \
      "notes[text]=Google Cloud console: https://console.cloud.google.com/apis/credentials?project=${project}" >/dev/null
    echo "created  $title"
    created=$((created + 1))
  fi
done < "$INPUT"

echo
echo "${created} created, ${updated} updated, ${skipped} skipped."

if [[ $DRY_RUN -eq 0 && $((created + updated)) -gt 0 ]]; then
  cat <<'NOTE'

Read one back with:
  op item get "Google OAuth - Plumb" --vault Kubernetes --fields label=client_id
  op item get "Google OAuth - Plumb" --vault Kubernetes --fields label=credential --reveal
NOTE
fi
