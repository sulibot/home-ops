#!/usr/bin/env bash
# Bootstrap the OpenBao integrations tracked by ENG-346. Secret material is
# read at runtime from 1Password or Kubernetes and is never written to the
# repository, Terraform state, or command output.
set -euo pipefail
on_error() {
  local code="$1"
  local line="$2"
  echo "OpenBao integration reconciliation failed at line $line (exit $code)" >&2
  exit "$code"
}
trap 'on_error "$?" "$LINENO"' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
policy_dir="$script_dir/policies"

export BAO_ADDR="${BAO_ADDR:-https://openbao.sulibot.com}"
export VAULT_ADDR="$BAO_ADDR"
onepassword_vault="${OPENBAO_1PASSWORD_VAULT:-Kubernetes}"
using_connect=false
if [[ -n "${OP_CONNECT_HOST:-}" && -n "${OP_CONNECT_TOKEN:-}" ]]; then
  using_connect=true
else
  op whoami >/dev/null
fi

if command -v bao >/dev/null 2>&1; then
  bao_command=(bao)
elif command -v nix >/dev/null 2>&1; then
  bao_command=(nix shell nixpkgs#openbao -c bao)
else
  echo "OpenBao CLI or Nix is required" >&2
  exit 1
fi

bao_cli() {
  "${bao_command[@]}" "$@"
}

read_op_field() {
  local item="$1"
  shift
  local label value
  if [[ "$using_connect" == "true" ]]; then
    local item_json
    item_json="$(
      op item get "$item" --vault "$onepassword_vault" --format=json 2>/dev/null
    )" || return 1
    for label in "$@"; do
      value="$(
        jq -r --arg label "$label" '
          .fields[] |
          select(.label == $label or .id == $label) |
          .value // empty
        ' <<<"$item_json" |
          head -n1
      )"
      if [[ -n "$value" ]]; then
        printf '%s' "$value"
        return 0
      fi
    done
    return 1
  fi
  for label in "$@"; do
    value="$(
      op item get "$item" --vault "$onepassword_vault" \
        --fields "label=$label" --reveal 2>/dev/null || true
    )"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

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

BAO_TOKEN="$(
  read_op_field openbao-root-token password token credential
)"
export BAO_TOKEN
export VAULT_TOKEN="$BAO_TOKEN"

if [[ -z "$BAO_TOKEN" ]]; then
  echo "could not read the OpenBao root token from 1Password" >&2
  exit 1
fi

bao_cli token lookup -format=json |
  jq -e '.data.policies | index("root")' >/dev/null

for policy_file in "$policy_dir"/*.hcl; do
  policy_name="$(basename "$policy_file" .hcl)"
  bao_cli policy write "$policy_name" "$policy_file" >/dev/null
done

if ! bao_cli secrets list -format=json | jq -e 'has("kv/")' >/dev/null; then
  bao_cli secrets enable -path=kv -version=2 kv >/dev/null
fi

if ! bao_cli secrets list -format=json | jq -e 'has("transit/")' >/dev/null; then
  bao_cli secrets enable -path=transit transit >/dev/null
fi
if ! bao_cli read transit/keys/sops >/dev/null 2>&1; then
  bao_cli write -f transit/keys/sops type=aes256-gcm96 >/dev/null
fi

# OpenBao 2.6 manages audit devices declaratively in openbao.hcl. Refuse to
# continue if the rolling node configuration has not activated both devices.
if ! bao_cli audit list -format=json |
  jq -e 'has("file/") and has("syslog/")' >/dev/null; then
  echo "declarative OpenBao audit devices are not active; run rolling-reconcile.sh first" >&2
  exit 1
fi

# Kubernetes auth uses the authenticating External Secrets service-account JWT
# as its reviewer JWT. This avoids a long-lived reviewer token on OpenBao.
kubernetes_host="$(
  kubectl config view --raw --minify \
    -o jsonpath='{.clusters[0].cluster.server}'
)"
kubernetes_issuer="$(
  token="$(
    kubectl -n external-secrets create token external-secrets \
      --audience=openbao --duration=10m
  )"
  payload="${token#*.}"
  payload="${payload%%.*}"
  payload_modulo="${#payload}"
  payload_modulo=$((payload_modulo % 4))
  if [[ "$payload_modulo" -eq 2 ]]; then
    payload="${payload}=="
  elif [[ "$payload_modulo" -eq 3 ]]; then
    payload="${payload}="
  fi
  printf '%s' "$payload" | tr '_-' '/+' | base64 --decode 2>/dev/null |
    jq -er '.iss'
)"
kubernetes_ca_file="$(mktemp)"
trap 'find "$kubernetes_ca_file" -type f -delete 2>/dev/null || true' EXIT
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' |
  base64 --decode >"$kubernetes_ca_file"

if ! bao_cli auth list -format=json | jq -e 'has("kubernetes/")' >/dev/null; then
  bao_cli auth enable -path=kubernetes kubernetes >/dev/null
fi
bao_cli write auth/kubernetes/config \
  kubernetes_host="$kubernetes_host" \
  kubernetes_ca_cert=@"$kubernetes_ca_file" \
  issuer="$kubernetes_issuer" \
  disable_local_ca_jwt=true >/dev/null
bao_cli write auth/kubernetes/role/external-secrets \
  audience=openbao \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  token_policies=external-secrets \
  token_ttl=15m \
  token_max_ttl=1h >/dev/null

# Seed pilots from the currently rendered Secrets so each cutover is a
# byte-for-byte source change, not a simultaneous credential rotation.
pilot_file="$(mktemp)"
radarr_pilot_file="$(mktemp)"
trap 'find "$kubernetes_ca_file" "$pilot_file" "$radarr_pilot_file" -type f -delete 2>/dev/null || true' EXIT
kubectl -n default get secret immich-frame-secret -o json |
  jq -e '.data | with_entries(.value |= @base64d)' >"$pilot_file"
bao_cli kv put -mount=kv kubernetes/immich-frame @"$pilot_file" >/dev/null

kubectl -n default get secret radarr-4k-secret -o json |
  jq -e '{
    RADARR_API_KEY: (.data.RADARR__AUTH__APIKEY | @base64d),
    DB_PASSWORD: (.data.RADARR__POSTGRES__PASSWORD | @base64d)
  }' >"$radarr_pilot_file"
kubectl -n default get secret radarr-4k-pg-password -o json |
  jq -e --slurpfile app "$radarr_pilot_file" '
    (.data.password | @base64d) == $app[0].DB_PASSWORD
  ' >/dev/null
bao_cli kv put -mount=kv kubernetes/radarr-4k @"$radarr_pilot_file" >/dev/null

if ! bao_cli auth list -format=json | jq -e 'has("approle/")' >/dev/null; then
  bao_cli auth enable -path=approle approle >/dev/null
fi

upsert_approle_item() {
  local role_name="$1"
  local policy_name="$2"
  local item_name="openbao-approle-$role_name"
  local role_id secret_id item_json

  bao_cli write "auth/approle/role/$role_name" \
    bind_secret_id=true \
    secret_id_num_uses=0 \
    secret_id_ttl=0 \
    token_policies="$policy_name" \
    token_type=batch \
    token_ttl=1h \
    token_max_ttl=4h >/dev/null
  role_id="$(bao_cli read -field=role_id "auth/approle/role/$role_name/role-id")"

  if item_json="$(
    op item get "$item_name" --vault "$onepassword_vault" --format=json 2>/dev/null
  )"; then
    existing_role_id="$(jq -r '.fields[] | select(.id == "username") | .value // empty' <<<"$item_json")"
    existing_secret_id="$(jq -r '.fields[] | select(.id == "password") | .value // empty' <<<"$item_json")"
    if [[ "$existing_role_id" == "$role_id" ]] &&
      [[ -n "$existing_secret_id" ]] &&
      bao_cli write -format=json auth/approle/login \
        role_id="$existing_role_id" \
        secret_id="$existing_secret_id" |
        jq -e '.auth.client_token | length > 0' >/dev/null; then
      return 0
    fi
  fi

  secret_id="$(
    bao_cli write -f -field=secret_id \
      "auth/approle/role/$role_name/secret-id"
  )"

  if [[ -n "${item_json:-}" ]]; then
    updated_item="$(
      jq --arg role_id "$role_id" --arg secret_id "$secret_id" '
        .fields |= map(
          if .id == "username" then .value = $role_id
          elif .id == "password" then .value = $secret_id
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
        op item edit "$item_name" --vault "$onepassword_vault" >/dev/null
    fi
  else
    item_payload="$(
      jq -n \
        --arg title "$item_name" \
        --arg role_id "$role_id" \
        --arg secret_id "$secret_id" \
        '{
          title: $title,
          category: "LOGIN",
          fields: [
            {
              id: "username",
              label: "role_id",
              type: "STRING",
              purpose: "USERNAME",
              value: $role_id
            },
            {
              id: "password",
              label: "secret_id",
              type: "CONCEALED",
              purpose: "PASSWORD",
              value: $secret_id
            }
          ],
          tags: ["openbao", "automation"]
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
}

upsert_approle_item tofu homeops-tofu
upsert_approle_item ansible homeops-ansible
upsert_approle_item sops sops-transit
upsert_approle_item backup openbao-snapshot
upsert_approle_item mtls cloudflare-mtls
upsert_approle_item agent-devbox agent-devbox

# GitHub Actions exchanges its job-scoped OIDC token directly for a short-lived
# OpenBao batch token. The role is deliberately restricted to this repository,
# its owner, the Terraform plan workflow, the protected environment, and the
# repository owner's immutable actor ID. Fork PRs cannot satisfy these claims.
if ! bao_cli auth list -format=json | jq -e 'has("jwt-github/")' >/dev/null; then
  bao_cli auth enable -path=jwt-github jwt >/dev/null
fi
bao_cli write auth/jwt-github/config \
  oidc_discovery_url=https://token.actions.githubusercontent.com >/dev/null
bao_cli write auth/jwt-github/role/terraform-plan - <<'EOF' >/dev/null
{
  "role_type": "jwt",
  "user_claim": "repository_id",
  "bound_audiences": ["https://openbao.sulibot.com"],
  "bound_claims_type": "glob",
  "bound_claims": {
    "repository_id": "912241670",
    "repository_owner_id": "6082800",
    "actor_id": "6082800",
    "event_name": "pull_request",
    "base_ref": "main",
    "environment": "terraform-plan",
    "runner_environment": "self-hosted",
    "workflow_ref": "sulibot/home-ops/.github/workflows/terraform-plan.yml@refs/pull/*/merge"
  },
  "token_policies": ["github-actions-sops"],
  "token_type": "batch",
  "token_ttl": "10m",
  "token_max_ttl": "10m",
  "token_explicit_max_ttl": "10m"
}
EOF

# Manual device certificate lifecycle operations run only from the protected
# main branch workflow, on the self-hosted runner, and for the repository owner.
bao_cli write auth/jwt-github/role/cloudflare-mtls-device - <<'EOF' >/dev/null
{
  "role_type": "jwt",
  "user_claim": "repository_id",
  "bound_audiences": ["https://openbao.sulibot.com"],
  "bound_claims_type": "glob",
  "bound_claims": {
    "repository_id": "912241670",
    "repository_owner_id": "6082800",
    "actor_id": "6082800",
    "event_name": "workflow_dispatch",
    "ref": "refs/heads/main",
    "environment": "cloudflare-mtls-issuance",
    "runner_environment": "self-hosted",
    "workflow_ref": "sulibot/home-ops/.github/workflows/cloudflare-mtls-device.yml@refs/heads/main"
  },
  "token_policies": ["cloudflare-mtls"],
  "token_type": "batch",
  "token_ttl": "10m",
  "token_max_ttl": "10m",
  "token_explicit_max_ttl": "10m"
}
EOF

# The scheduled audit can read device identities and expiry metadata through
# the same least-privilege policy, but its OIDC role cannot mutate the workflow
# binding or run from a pull request.
bao_cli write auth/jwt-github/role/cloudflare-mtls-monitor - <<'EOF' >/dev/null
{
  "role_type": "jwt",
  "user_claim": "repository_id",
  "bound_audiences": ["https://openbao.sulibot.com"],
  "bound_claims_type": "glob",
  "bound_claims": {
    "repository_id": "912241670",
    "repository_owner_id": "6082800",
    "event_name": "schedule",
    "ref": "refs/heads/main",
    "environment": "cloudflare-mtls-monitoring",
    "runner_environment": "self-hosted",
    "workflow_ref": "sulibot/home-ops/.github/workflows/cloudflare-mtls-expiry.yml@refs/heads/main"
  },
  "token_policies": ["cloudflare-mtls-monitor"],
  "token_type": "batch",
  "token_ttl": "10m",
  "token_max_ttl": "10m",
  "token_explicit_max_ttl": "10m"
}
EOF

# Reconcile Kanidm OIDC after its confidential client has been created. The
# client bootstrap script stores the secret in 1Password as openbao-oidc.
if oidc_secret="$(read_op_field openbao-oidc password client_secret 2>/dev/null)"; then
  if ! bao_cli auth list -format=json | jq -e 'has("oidc/")' >/dev/null; then
    bao_cli auth enable -path=oidc oidc >/dev/null
  fi
  bao_cli write auth/oidc/config \
    oidc_discovery_url=https://idm.sulibot.com/oauth2/openid/openbao \
    oidc_client_id=openbao \
    oidc_client_secret="$oidc_secret" \
    default_role=kanidm >/dev/null
  bao_cli write auth/oidc/role/kanidm \
    bound_audiences=openbao \
    allowed_redirect_uris=https://openbao.sulibot.com/ui/vault/auth/oidc/oidc/callback \
    allowed_redirect_uris=http://localhost:8250/oidc/callback \
    user_claim=preferred_username \
    groups_claim=groups \
    oidc_scopes=openid,profile,email,groups_name \
    token_policies=default \
    token_ttl=1h \
    token_max_ttl=8h >/dev/null

  oidc_accessor="$(
    bao_cli auth list -format=json | jq -er '."oidc/".accessor'
  )"

  ensure_identity_group_alias() {
    local kanidm_group="$1"
    local bao_group="$2"
    local policy="$3"
    local group_id alias_id alias_listing

    group_id="$(
      bao_cli read -field=id "identity/group/name/$bao_group" 2>/dev/null ||
        bao_cli write -format=json identity/group \
          name="$bao_group" type=external policies="$policy" |
        jq -er '.data.id'
    )"
    bao_cli write "identity/group/id/$group_id" policies="$policy" >/dev/null

    alias_listing="$(
      bao_cli list -format=json identity/group-alias/id 2>/dev/null || true
    )"
    if [[ -n "$alias_listing" ]]; then
      alias_id="$(
        printf '%s' "$alias_listing" |
        jq -r 'if type == "array" then .[] else .data.keys[]? end' |
        while read -r candidate; do
          bao_cli read -format=json "identity/group-alias/id/$candidate" 2>/dev/null |
            jq -r --arg name "$kanidm_group" --arg accessor "$oidc_accessor" '
              select(.data.name == $name and .data.mount_accessor == $accessor) |
              .data.id
            '
        done |
        head -n1
      )"
    else
      alias_id=""
    fi
    if [[ -n "$alias_id" ]]; then
      bao_cli write "identity/group-alias/id/$alias_id" \
        name="$kanidm_group" \
        mount_accessor="$oidc_accessor" \
        canonical_id="$group_id" >/dev/null
    else
      bao_cli write identity/group-alias \
        name="$kanidm_group" \
        mount_accessor="$oidc_accessor" \
        canonical_id="$group_id" >/dev/null
    fi
  }

  ensure_identity_group_alias openbao-admins kanidm-openbao-admins openbao-admin
  ensure_identity_group_alias openbao-readers kanidm-openbao-readers openbao-reader
else
  echo "Kanidm client openbao-oidc is not available yet; OIDC reconciliation skipped" >&2
fi

bao_cli audit list -format=json |
  jq -e 'has("file/") and has("syslog/")' >/dev/null
bao_cli read transit/keys/sops -format=json |
  jq -e '.data.name == "sops"' >/dev/null

echo "OpenBao policies, audit, Kubernetes auth, pilot seed, AppRoles, and Transit are reconciled"
