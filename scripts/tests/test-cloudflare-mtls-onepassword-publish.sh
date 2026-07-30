#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
device_script="$repo_root/scripts/cloudflare-mtls-device.sh"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/test-cloudflare-mtls-publish.XXXXXX")"
cleanup() {
  find "$work_dir" -type f -delete 2>/dev/null || true
  find "$work_dir" -type d -depth -exec rmdir {} \; 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$work_dir/bin"
inventory="$work_dir/devices.json"
mock_curl="$work_dir/bin/curl"
mock_op="$work_dir/bin/op"
profile_content='test mobileconfig contents'
profile_base64="$(printf '%s' "$profile_content" | base64 | tr -d '\n')"

printf '%s\n' '{
  "schema_version": 1,
  "devices": [{
    "id": "device-a",
    "display_name": "Device A",
    "owner": "test",
    "device": "a",
    "platform": "macos"
  }]
}' >"$inventory"

cat >"$mock_curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url="${*: -1}"
if [[ "$url" == */v1/kv/data/automation/cloudflare-mtls/config ]]; then
  jq -cn '{
    data: {
      data: {
        onepassword_service_account_token: "mock-service-account-token",
        onepassword_vault: "Kubernetes"
      }
    }
  }'
  exit 0
fi

if [[ "$url" == */v1/kv/data/automation/cloudflare-mtls/identities/device-a/current ]]; then
  jq -cn --arg profile "$MOCK_PROFILE_BASE64" '{
    data: {
      data: {
        status: "active",
        cloudflare_certificate_id: "mock-certificate-id",
        profile_file_name: "test-a-macos.mobileconfig",
        mobileconfig_base64: $profile
      }
    }
  }'
  exit 0
fi

echo "unexpected mock curl request: $url" >&2
exit 22
EOF
chmod +x "$mock_curl"

cat >"$mock_op" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "${OP_SERVICE_ACCOUNT_TOKEN:-}" == "mock-service-account-token" ]]
command_name="${1:-} ${2:-}"
case "$command_name" in
  "item list")
    if [[ -f "$MOCK_OP_STATE" ]]; then
      title="$(<"$MOCK_OP_STATE")"
      jq -cn --arg title "$title" \
        '[{id:"mock-document-id",title:$title,category:"DOCUMENT"}]'
    else
      jq -cn '[]'
    fi
    ;;
  "document create")
    profile_file="$3"
    shift 3
    title=""
    vault=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --title)
          title="$2"
          shift 2
          ;;
        --vault)
          vault="$2"
          shift 2
          ;;
        --file-name | --tags)
          shift 2
          ;;
        *)
          exit 2
          ;;
      esac
    done
    [[ "$vault" == "Kubernetes" ]]
    cp "$profile_file" "$MOCK_OP_DOCUMENT"
    printf '%s' "$title" >"$MOCK_OP_STATE"
    printf '1\n' >>"$MOCK_OP_CREATE_COUNT"
    jq -cn '{id:"mock-document-id"}'
    ;;
  "document get")
    [[ "$3" == "mock-document-id" ]]
    shift 3
    output_file=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --vault)
          [[ "$2" == "Kubernetes" ]]
          shift 2
          ;;
        --out-file)
          output_file="$2"
          shift 2
          ;;
        *)
          exit 2
          ;;
      esac
    done
    cp "$MOCK_OP_DOCUMENT" "$output_file"
    ;;
  *)
    echo "unexpected mock op command: $command_name" >&2
    exit 2
    ;;
esac
EOF
chmod +x "$mock_op"

common_env=(
  "PATH=$work_dir/bin:$PATH"
  "VAULT_ADDR=https://openbao.example.invalid"
  "VAULT_TOKEN=mock-openbao-token"
  "MOCK_PROFILE_BASE64=$profile_base64"
  "MOCK_OP_STATE=$work_dir/op-state"
  "MOCK_OP_DOCUMENT=$work_dir/1password.mobileconfig"
  "MOCK_OP_CREATE_COUNT=$work_dir/op-create-count"
)

first_output="$(
  env "${common_env[@]}" \
    "$device_script" export \
      --device-id device-a \
      --inventory "$inventory" \
      --onepassword-vault Kubernetes
)"
second_output="$(
  env "${common_env[@]}" \
    "$device_script" export \
      --device-id device-a \
      --inventory "$inventory" \
      --onepassword-vault Kubernetes
)"

grep -q 'created 1Password document in vault: Kubernetes' <<<"$first_output"
grep -q '1Password document already current in vault: Kubernetes' \
  <<<"$second_output"
[[ "$(<"$work_dir/1password.mobileconfig")" == "$profile_content" ]]
[[ "$(wc -l <"$work_dir/op-create-count" | tr -d ' ')" == "1" ]]

echo "Cloudflare mTLS 1Password publication tests passed"
