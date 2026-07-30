#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
device_script="$repo_root/scripts/cloudflare-mtls-device.sh"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/test-cloudflare-mtls-issue.XXXXXX")"
cleanup() {
  find "$work_dir" -type f -delete 2>/dev/null || true
  find "$work_dir" -type d -depth -exec rmdir {} \; 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$work_dir/bin" "$work_dir/captures"
inventory="$work_dir/devices.json"
mock_curl="$work_dir/bin/curl"
ca_key="$work_dir/ca-key.pem"
ca_cert="$work_dir/ca-cert.pem"
profile="$work_dir/device-a.mobileconfig"

cat >"$inventory" <<'EOF'
{
  "schema_version": 1,
  "devices": [
    {
      "id": "device-a",
      "display_name": "Device A",
      "owner": "test",
      "device": "a",
      "platform": "macos"
    }
  ]
}
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$ca_key" \
  -out "$ca_cert" \
  -days 2 \
  -subj "/CN=Test Cloudflare CA" >/dev/null 2>&1

cat >"$mock_curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

method="GET"
data_file=""
args=("$@")
for ((index = 0; index < ${#args[@]}; index++)); do
  case "${args[$index]}" in
    --request)
      method="${args[$((index + 1))]}"
      ;;
    --data-binary)
      data_file="${args[$((index + 1))]#@}"
      ;;
  esac
done
url="${args[${#args[@]} - 1]}"

if [[ "$url" == */v1/kv/data/automation/cloudflare-mtls/config ]]; then
  jq -cn '{
    data: {
      data: {
        cloudflare_api_token: "mock-token",
        cloudflare_zone_id: "mock-zone"
      }
    }
  }'
  exit 0
fi

if [[ "$url" == */v1/kv/data/automation/cloudflare-mtls/identities/device-a/current ]] &&
  [[ "$method" == "GET" ]]; then
  exit 22
fi

if [[ "$url" == https://api.cloudflare.com/*/client_certificates ]] &&
  [[ "$method" == "POST" ]]; then
  csr_file="$MOCK_CAPTURE_DIR/request.csr"
  certificate_file="$MOCK_CAPTURE_DIR/client-cert.pem"
  jq -er '.csr' "$data_file" >"$csr_file"
  openssl x509 -req \
    -in "$csr_file" \
    -CA "$MOCK_CA_CERT" \
    -CAkey "$MOCK_CA_KEY" \
    -CAcreateserial \
    -days 365 \
    -out "$certificate_file" >/dev/null 2>&1
  certificate="$(<"$certificate_file")"
  end_date="$(openssl x509 -in "$certificate_file" -noout -enddate | cut -d= -f2-)"
  if date -u -j -f "%b %e %T %Y %Z" "$end_date" \
    +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    expires="$(date -u -j -f "%b %e %T %Y %Z" "$end_date" +%Y-%m-%dT%H:%M:%SZ)"
  else
    expires="$(date -u -d "$end_date" +%Y-%m-%dT%H:%M:%SZ)"
  fi
  jq -cn \
    --arg certificate "$certificate" \
    --arg expires "$expires" \
    '{
      success: true,
      result: {
        id: "mock-certificate-id",
        certificate: $certificate,
        certificate_authority: {
          id: "mock-ca-id",
          name: "Mock Cloudflare Managed CA"
        },
        serial_number: "0123456789abcdef",
        fingerprint_sha256: "abcdef",
        issued_on: "2026-07-29T00:00:00Z",
        expires_on: $expires,
        validity_days: 365,
        status: "active"
      }
    }'
  exit 0
fi

if [[ "$url" == */v1/kv/data/automation/cloudflare-mtls/* ]] &&
  [[ "$method" == "POST" ]]; then
  capture_name="${url#*/v1/kv/data/automation/cloudflare-mtls/}"
  capture_name="${capture_name//\//_}"
  cp "$data_file" "$MOCK_CAPTURE_DIR/$capture_name.json"
  jq -cn '{}'
  exit 0
fi

echo "unexpected mock curl request: $method $url" >&2
exit 22
EOF
chmod +x "$mock_curl"

PATH="$work_dir/bin:$PATH" \
  VAULT_ADDR="https://openbao.example.invalid" \
  VAULT_TOKEN="mock-openbao-token" \
  MOCK_CAPTURE_DIR="$work_dir/captures" \
  MOCK_CA_CERT="$ca_cert" \
  MOCK_CA_KEY="$ca_key" \
  "$device_script" issue \
    --device-id device-a \
    --inventory "$inventory" \
    --output "$profile" >/dev/null

identity_payload="$work_dir/captures/identities_device-a_current.json"
metadata_payload="$work_dir/captures/inventory_device-a_current.json"
test -s "$profile"
jq -e '
  (.data.private_key_pem | contains("PRIVATE KEY")) and
  (.data.mobileconfig_base64 | length > 0) and
  (.data.status == "active")
' "$identity_payload" >/dev/null
jq -e '
  (.data.status == "active") and
  (.data.serial_number == "0123456789abcdef") and
  (has("private_key_pem") | not) and
  (has("pkcs12_password") | not) and
  (has("mobileconfig_base64") | not)
' "$metadata_payload" >/dev/null
grep -q "<key>AllowAllAppsAccess</key>" "$profile"

echo "Cloudflare mTLS issuance pipeline tests passed"
