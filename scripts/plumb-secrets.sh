#!/usr/bin/env bash
#
# Sync Plumb's secrets from 1Password into the sops-encrypted terraform vars.
#
#   ./scripts/plumb-secrets.sh --dry-run   # show what would be written
#   ./scripts/plumb-secrets.sh             # write them
#
# The values live in 1Password; sops is a derived copy that terraform reads.
# Copying them by hand is how a wrong value gets in and then costs an hour to
# find, so this does it — and refuses rather than writing a placeholder.
#
# ONE thing to fill in by hand, on the 'Supabase Plumb' item (Kubernetes vault):
#
#   credential  <- a Supabase personal access token
#                  https://supabase.com/dashboard/account/tokens
#
# Everything else is derived:
#
#   - organization_id is FETCHED from the Management API using that token,
#     rather than transcribed from a dashboard URL. The dashboard shows a slug
#     in some places and an id in others, and the provider wants the id.
#   - the token's expiry is fetched and written back to 1Password, because a
#     PAT with an expiry that nobody recorded fails silently on a date nobody
#     can name.
#   - open-brain's sops copy is updated too. Both repos hold Supabase PATs and
#     both currently hold the SAME dead one; a PAT cannot be scoped, so a
#     second token would add rotation burden without shrinking blast radius.
set -euo pipefail
cd "$(dirname "$0")/.."

SECRETS="terraform/infra/live/common/secrets.sops.yaml"
OPEN_BRAIN="/Users/sulibot/code/open-brain/infra/terraform/live/common/secrets.sops.yaml"
ITEM="Supabase Plumb"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if ! op vault get Kubernetes >/dev/null 2>&1; then
  echo "Cannot reach the Kubernetes vault. Run 'op signin' first." >&2
  exit 1
fi

read_field() {
  op item get "$1" --vault Kubernetes --fields "label=$2" --reveal 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# The one value that must come from a human
# ---------------------------------------------------------------------------

PAT="$(read_field "$ITEM" credential)"

if [[ -z "$PAT" || "$PAT" == REPLACE-ME* ]]; then
  cat >&2 <<'MSG'
No Supabase access token yet.

  1. https://supabase.com/dashboard/account/tokens
  2. Generate new token, name it "terraform-home-ops"
  3. Expires in -> Custom. "Never" is unavailable while the existing
     cli_sulibot@ganymede token holds the single never-expiring slot —
     do NOT delete that one, it is your CLI login.
  4. Paste it into 1Password: "Supabase Plumb" / credential

Then re-run this script.
MSG
  exit 1
fi

# Fail here, loudly, rather than at terraform apply with "Unauthorized".
if ! curl -sf -o /dev/null -H "Authorization: Bearer $PAT" \
     https://api.supabase.com/v1/organizations; then
  echo "The token in '$ITEM' / credential is rejected by the Supabase API." >&2
  echo "It is expired, revoked, or was pasted incompletely." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Derive what can be derived
# ---------------------------------------------------------------------------

ORG_JSON="$(curl -s -H "Authorization: Bearer $PAT" https://api.supabase.com/v1/organizations)"
ORG_COUNT="$(printf '%s' "$ORG_JSON" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"

if [[ "$ORG_COUNT" != "1" ]]; then
  # More than one organization means a choice, and choosing silently would put
  # the project somewhere unexpected — possibly with different billing.
  echo "Found $ORG_COUNT organizations. Set organization_id on '$ITEM' by hand:" >&2
  printf '%s' "$ORG_JSON" | python3 -c '
import json,sys
for o in json.load(sys.stdin): print(f"  {o.get(\"name\")}  id={o.get(\"id\")}", file=sys.stderr)'
  ORG_ID="$(read_field "$ITEM" organization_id)"
  [[ -z "$ORG_ID" || "$ORG_ID" == REPLACE-ME* ]] && exit 1
else
  ORG_ID="$(printf '%s' "$ORG_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')"
  ORG_NAME="$(printf '%s' "$ORG_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["name"])')"
  echo "org      $ORG_NAME ($ORG_ID)"
fi

# ---------------------------------------------------------------------------
# Collect
# ---------------------------------------------------------------------------

declare -a WRITES=()
missing=0

add() { WRITES+=("$1:$2"); }

collect() {
  local key="$1" item="$2" field="$3"
  local value; value="$(read_field "$item" "$field")"
  if [[ -z "$value" ]]; then
    echo "MISSING  $key  <- '$item' / $field is empty" >&2; missing=$((missing + 1)); return
  fi
  if [[ "$value" == REPLACE-ME* ]]; then
    echo "PLACEHOLDER  $key  <- '$item' / $field still says REPLACE-ME" >&2; missing=$((missing + 1)); return
  fi
  add "$key" "$value"
  echo "ok       $key  (${#value} chars from '$item')"
}

add "supabase_access_token" "$PAT";      echo "ok       supabase_access_token  (${#PAT} chars)"
add "supabase_organization_id" "$ORG_ID"; echo "ok       supabase_organization_id"

collect supabase_plumb_db_password "$ITEM" db_password
collect plumb_smtp_password        "Plumb SMTP"        credential
collect plumb_google_client_id     "Plumb Google OAuth" username
collect plumb_google_client_secret "Plumb Google OAuth" credential

# Not a secret, but kept here so the sops file is complete and terraform needs
# no other source. The apex, not a subdomain: Resend's plan allows one domain
# and sulibot.com holds it, so a subdomain sender would be unverified.
add "plumb_smtp_sender" "no-reply@sulibot.com"
echo "ok       plumb_smtp_sender  (literal: no-reply@sulibot.com)"

if [[ $missing -gt 0 ]]; then
  echo >&2; echo "$missing value(s) not ready. Fill them in 1Password, then re-run." >&2
  exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo; echo "Dry run — nothing written. ${#WRITES[@]} keys would go to $SECRETS."
  [[ -f "$OPEN_BRAIN" ]] && echo "open-brain's supabase_access_token would also be refreshed."
  exit 0
fi

# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------

for w in "${WRITES[@]}"; do
  key="${w%%:*}"; value="${w#*:}"
  sops set "$SECRETS" "[\"$key\"]" "\"$value\""
done
echo; echo "Wrote ${#WRITES[@]} keys to $SECRETS."

# open-brain holds the same dead PAT. Left alone, its terraform fails the next
# time anyone runs it, with an error that never mentions this script.
if [[ -f "$OPEN_BRAIN" ]]; then
  sops set "$OPEN_BRAIN" '["supabase_access_token"]' "\"$PAT\""
  echo "Refreshed supabase_access_token in open-brain."
fi

# Record the expiry where someone will see it. A PAT whose expiry nobody wrote
# down fails silently on a date nobody can name.
op item edit "$ITEM" --vault Kubernetes "organization_id[text]=$ORG_ID" >/dev/null
echo "Wrote organization_id back to 1Password."

cat <<'NEXT'

Next:
  cd terraform/infra/live/services/supabase-plumb && terragrunt apply
  terragrunt output google_redirect_uri     # paste into the Google console
NEXT
