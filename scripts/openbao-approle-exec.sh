#!/usr/bin/env bash
# Run one command with a short-lived, scoped OpenBao batch token obtained from
# an AppRole credential stored in 1Password.
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "usage: $0 {tofu|ansible|sops|mtls|agent-devbox} command [args...]" >&2
  exit 2
fi

role="$1"
shift
case "$role" in
  tofu | ansible | sops | mtls | agent-devbox) ;;
  *)
    echo "unsupported OpenBao automation role: $role" >&2
    exit 2
    ;;
esac

export BAO_ADDR="${BAO_ADDR:-https://openbao.sulibot.com}"
export VAULT_ADDR="$BAO_ADDR"
onepassword_vault="${OPENBAO_1PASSWORD_VAULT:-Kubernetes}"
item_name="openbao-approle-$role"

item_json="$(
  op item get "$item_name" --vault "$onepassword_vault" --format=json
)"
role_id="$(
  jq -er '.fields[] | select(.id == "username") | .value' <<<"$item_json"
)"
secret_id="$(
  jq -er '.fields[] | select(.id == "password") | .value' <<<"$item_json"
)"
unset item_json

login_payload="$(
  jq -cn --arg role_id "$role_id" --arg secret_id "$secret_id" \
    '{role_id:$role_id,secret_id:$secret_id}'
)"
login_response="$(
  printf '%s' "$login_payload" |
    curl --silent --show-error --fail-with-body \
      --header 'content-type: application/json' \
      --request POST \
      --data-binary @- \
      "$BAO_ADDR/v1/auth/approle/login"
)"
BAO_TOKEN="$(jq -er '.auth.client_token' <<<"$login_response")"
export BAO_TOKEN
export VAULT_TOKEN="$BAO_TOKEN"
unset role_id secret_id login_payload login_response

exec "$@"
