#!/usr/bin/env bash
# Create the Kanidm groups and confidential OIDC client used by OpenBao.
# Authentication is performed through Kanidm's stepped REST API so no
# password is exposed through an interactive CLI or process arguments.
set -euo pipefail
on_error() {
  local code="$1"
  local line="$2"
  echo "Kanidm OIDC reconciliation failed at line $line (exit $code)" >&2
  exit "$code"
}
trap 'on_error "$?" "$LINENO"' ERR

kanidm_node="${KANIDM_BOOTSTRAP_NODE:-10.100.0.61}"
kanidm_origin="https://idm.sulibot.com"
kanidm_direct_url="https://idm.sulibot.com:8443"
onepassword_vault="${OPENBAO_1PASSWORD_VAULT:-Kubernetes}"
human_email="${OPENBAO_ADMIN_EMAIL:-sulibot@gmail.com}"
human_name_default="${OPENBAO_ADMIN_KANIDM_USER:-sulibot}"
human_display_name="${OPENBAO_ADMIN_DISPLAY_NAME:-Sulaiman Ahmad}"
human_credential_item="${OPENBAO_ADMIN_1PASSWORD_ITEM:-kanidm-sulibot}"

using_connect=false
if [[ -n "${OP_CONNECT_HOST:-}" && -n "${OP_CONNECT_TOKEN:-}" ]]; then
  using_connect=true
else
  op whoami >/dev/null
fi

connect_write_item() {
  local method="$1"
  local path="$2"
  local payload="$3"
  printf '%s' "$payload" |
    curl --silent --show-error --fail-with-body \
      --config <(
        printf 'header = "Authorization: Bearer %s"\n' "$OP_CONNECT_TOKEN"
      ) \
      --header 'content-type: application/json' \
      --request "$method" \
      --data-binary @- \
      --output /dev/null \
      "${OP_CONNECT_HOST%/}$path"
}

if [[ "$using_connect" == "true" ]]; then
  admin_password="$(
    op item get kanidm --vault "$onepassword_vault" --format=json |
      jq -er '.fields[] | select(.label == "password") | .value'
  )"
else
  admin_password="$(
    op item get kanidm --vault "$onepassword_vault" \
      --fields label=password --reveal
  )"
fi
if [[ -z "$admin_password" ]]; then
  echo "could not read the Kanidm idm_admin credential from 1Password" >&2
  exit 1
fi

curl_common=(
  --silent
  --show-error
  --fail-with-body
  --resolve "idm.sulibot.com:8443:$kanidm_node"
  --header "content-type: application/json"
)

header_file="$(mktemp)"
init_body="$(mktemp)"
trap 'find "$header_file" "$init_body" -type f -delete 2>/dev/null || true' EXIT

printf '%s' \
  '{"step":{"init2":{"username":"idm_admin","issue":"token","privileged":true}}}' |
  curl "${curl_common[@]}" \
    --dump-header "$header_file" \
    --output "$init_body" \
    --request POST \
    --data-binary @- \
    "$kanidm_direct_url/v1/auth"

auth_session="$(
  awk '
    BEGIN { IGNORECASE=1 }
    /^x-kanidm-auth-session-id:/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      sub(/\r$/, "")
      print
    }
  ' "$header_file"
)"
if [[ -z "$auth_session" ]]; then
  echo "Kanidm did not return a signed authentication-session header" >&2
  exit 1
fi

printf '%s' '{"step":{"begin":"password"}}' |
  curl "${curl_common[@]}" \
    --header "x-kanidm-auth-session-id: $auth_session" \
    --request POST \
    --data-binary @- \
    "$kanidm_direct_url/v1/auth" |
  jq -e '.state.continue | index("password")' >/dev/null

credential_payload="$(
  jq -cn --arg password "$admin_password" \
    '{step:{cred:{password:$password}}}'
)"
credential_response="$(
  printf '%s' "$credential_payload" |
    curl "${curl_common[@]}" \
      --header "x-kanidm-auth-session-id: $auth_session" \
      --request POST \
      --data-binary @- \
      "$kanidm_direct_url/v1/auth"
)"
if ! jq -e '.state.success' >/dev/null <<<"$credential_response"; then
  jq -c '{authentication_state:.state}' <<<"$credential_response" >&2
  exit 1
fi
kanidm_token="$(jq -er '.state.success' <<<"$credential_response")"
unset admin_password credential_payload credential_response auth_session

kanidm_api() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  if [[ -n "$payload" ]]; then
    printf '%s' "$payload" |
      curl "${curl_common[@]}" \
        --header "Authorization: Bearer $kanidm_token" \
        --request "$method" \
        --data-binary @- \
        "$kanidm_direct_url$path"
  else
    curl "${curl_common[@]}" \
      --header "Authorization: Bearer $kanidm_token" \
      --request "$method" \
      "$kanidm_direct_url$path"
  fi
}

persons="$(kanidm_api GET /v1/person)"
matching_people="$(
  jq -c --arg email "$human_email" '
    [
      .[] |
      select((.attrs.mail // []) | index($email)) |
      .attrs.name[0]
    ]
  ' <<<"$persons"
)"
matching_people_count="$(jq -r 'length' <<<"$matching_people")"
case "$matching_people_count" in
  0)
    human_name="$human_name_default"
    if [[ "$(kanidm_api GET "/v1/person/$human_name")" == "null" ]]; then
      kanidm_api POST /v1/person \
        "$(
          jq -cn \
            --arg name "$human_name" \
            --arg display_name "$human_display_name" \
            '{attrs:{name:[$name],displayname:[$display_name]}}'
        )" >/dev/null
    fi
    kanidm_api PATCH "/v1/person/$human_name" \
      "$(
        jq -cn \
          --arg display_name "$human_display_name" \
          --arg email "$human_email" \
          '{attrs:{displayname:[$display_name],mail:[$email]}}'
      )" >/dev/null
    ;;
  1)
    human_name="$(jq -er '.[0]' <<<"$matching_people")"
    ;;
  *)
    echo "multiple Kanidm people have the requested OpenBao admin email" >&2
    exit 1
    ;;
esac
unset matching_people matching_people_count persons

ensure_group() {
  local group="$1"
  local current
  current="$(kanidm_api GET "/v1/group/$group")"
  if [[ "$current" == "null" ]]; then
    kanidm_api POST /v1/group \
      "$(jq -cn --arg name "$group" '{attrs:{name:[$name]}}')" >/dev/null
  fi
}

ensure_group openbao-admins
ensure_group openbao-readers
kanidm_api POST /v1/group/openbao-admins/_attr/member \
  "$(jq -cn --arg name "$human_name" '[$name]')" >/dev/null

# A newly-created person has no credential. Bootstrap a unique password only
# when its dedicated 1Password item does not exist, then leave later credential
# lifecycle (including passkey enrollment) to Kanidm and the user.
if ! op item get "$human_credential_item" \
  --vault "$onepassword_vault" --format=json >/dev/null 2>&1; then
  if [[ ! "$human_name" =~ ^[a-z0-9_.-]+$ ]]; then
    echo "refusing to recover a Kanidm account with an unsafe name" >&2
    exit 1
  fi
  ssh_options=(
    -i "${KANIDM_SSH_KEY:-$HOME/.ssh/id_ed25519}"
    -o BatchMode=yes
    -o ConnectTimeout=8
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
  )
  recovery_json="$(
    # The account name is deliberately expanded locally after validation.
    # shellcheck disable=SC2029
    ssh "${ssh_options[@]}" "root@$kanidm_node" \
      "kanidmd -c /etc/kanidmd/server.toml scripting recover-account '$human_name'"
  )"
  human_password="$(
    jq -er 'select(.status == "ok") | .output' <<<"$recovery_json"
  )"
  unset recovery_json
  sleep 3

  credential_item_payload="$(
    jq -n \
      --arg title "$human_credential_item" \
      --arg username "$human_name" \
      --arg password "$human_password" \
      --arg email "$human_email" \
      '{
        title: $title,
        category: "LOGIN",
        urls: [{href: "https://idm.sulibot.com"}],
        fields: [
          {
            id: "username",
            label: "username",
            type: "STRING",
            purpose: "USERNAME",
            value: $username
          },
          {
            id: "password",
            label: "password",
            type: "CONCEALED",
            purpose: "PASSWORD",
            value: $password
          },
          {
            label: "email",
            type: "STRING",
            value: $email
          }
        ],
        tags: ["kanidm", "openbao", "human-admin"]
      }'
  )"
  if [[ "$using_connect" == "true" ]]; then
    vault_id="$(
      op item get kanidm --vault "$onepassword_vault" --format=json |
        jq -er '.vault.id'
    )"
    credential_item_payload="$(
      jq --arg vault_id "$vault_id" \
        '.vault = {id:$vault_id}' <<<"$credential_item_payload"
    )"
    connect_write_item POST \
      "/v1/vaults/$vault_id/items" \
      "$credential_item_payload"
  else
    printf '%s' "$credential_item_payload" |
      op item create --vault "$onepassword_vault" - >/dev/null
  fi
  unset credential_item_payload human_password vault_id
fi

oauth_client="$(kanidm_api GET /v1/oauth2/openbao)"
if [[ "$oauth_client" == "null" ]]; then
  kanidm_api POST /v1/oauth2/_basic \
    '{
      "attrs": {
        "name": ["openbao"],
        "displayname": ["OpenBao"],
        "oauth2_rs_origin_landing": ["https://openbao.sulibot.com"],
        "oauth2_strict_redirect_uri": ["true"]
      }
    }' >/dev/null
fi

# Reconcile mutable client settings without resetting its generated secret.
kanidm_api PATCH /v1/oauth2/openbao \
  '{
    "attrs": {
      "displayname": ["OpenBao"],
      "oauth2_rs_origin_landing": ["https://openbao.sulibot.com"],
      "oauth2_strict_redirect_uri": ["true"],
      "oauth2_allow_insecure_client_disable_pkce": [],
      "oauth2_prefer_short_username": ["true"]
    }
  }' >/dev/null
kanidm_api POST /v1/oauth2/openbao/_attr/oauth2_rs_origin \
  '[
    "https://openbao.sulibot.com/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]' >/dev/null

scopes='["openid","profile","email","groups_name"]'
kanidm_api POST /v1/oauth2/openbao/_scopemap/openbao-admins "$scopes" >/dev/null
kanidm_api POST /v1/oauth2/openbao/_scopemap/openbao-readers "$scopes" >/dev/null

oidc_secret="$(kanidm_api GET /v1/oauth2/openbao/_basic_secret | jq -er '.')"
if [[ -z "$oidc_secret" ]]; then
  echo "Kanidm did not return the OpenBao OIDC client secret" >&2
  exit 1
fi

if item_json="$(
  op item get openbao-oidc --vault "$onepassword_vault" \
    --format=json 2>/dev/null
)"; then
  updated_item="$(
    jq --arg client_id openbao --arg client_secret "$oidc_secret" '
      .fields |= map(
        if .id == "username" then .value = $client_id
        elif .id == "password" then .value = $client_secret
        else .
        end
      )
    ' <<<"$item_json"
  )"
  if [[ "$using_connect" == "true" ]]; then
    item_id="$(jq -er '.id' <<<"$item_json")"
    vault_id="$(jq -er '.vault.id' <<<"$item_json")"
    connect_write_item PUT \
      "/v1/vaults/$vault_id/items/$item_id" \
      "$updated_item"
  else
    printf '%s' "$updated_item" |
      op item edit openbao-oidc --vault "$onepassword_vault" >/dev/null
  fi
else
  item_payload="$(
    jq -n --arg client_secret "$oidc_secret" '{
    title: "openbao-oidc",
    category: "LOGIN",
    urls: [{href: "https://idm.sulibot.com"}],
    fields: [
      {
        id: "username",
        label: "client_id",
        type: "STRING",
        purpose: "USERNAME",
        value: "openbao"
      },
      {
        id: "password",
        label: "client_secret",
        type: "CONCEALED",
        purpose: "PASSWORD",
        value: $client_secret
      }
    ],
    tags: ["openbao", "oidc", "kanidm"]
  }'
  )"
  if [[ "$using_connect" == "true" ]]; then
    vault_id="$(
      op item get kanidm --vault "$onepassword_vault" --format=json |
        jq -er '.vault.id'
    )"
    item_payload="$(
      jq --arg vault_id "$vault_id" \
        '.vault = {id:$vault_id}' <<<"$item_payload"
    )"
    connect_write_item POST \
      "/v1/vaults/$vault_id/items" \
      "$item_payload"
  else
    printf '%s' "$item_payload" |
      op item create --vault "$onepassword_vault" - >/dev/null
  fi
fi

unset oidc_secret kanidm_token

curl --silent --show-error --fail \
  --retry 12 \
  --retry-delay 1 \
  --retry-all-errors \
  "$kanidm_origin/oauth2/openid/openbao/.well-known/openid-configuration" |
  jq -e '
    .issuer == "https://idm.sulibot.com/oauth2/openid/openbao" and
    (.code_challenge_methods_supported | index("S256"))
  ' >/dev/null

echo "Kanidm OpenBao groups and OIDC client are reconciled"
