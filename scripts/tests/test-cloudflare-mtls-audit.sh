#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
device_script="$repo_root/scripts/cloudflare-mtls-device.sh"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/test-cloudflare-mtls-audit.XXXXXX")"
cleanup() {
  find "$work_dir" -type f -delete 2>/dev/null || true
  find "$work_dir" -type d -depth -exec rmdir {} \; 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$work_dir/bin"
inventory="$work_dir/devices.json"
mock_curl="$work_dir/bin/curl"

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
    },
    {
      "id": "device-not-issued",
      "display_name": "Device not issued",
      "owner": "test",
      "device": "missing",
      "platform": "ios"
    }
  ]
}
EOF

cat >"$mock_curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
if [[ "$url" == *"/inventory/device-a/current" ]]; then
  jq -cn --arg expires "$AUDIT_EXPIRES" \
    '{data:{data:{status:"active",expires_on:$expires}}}'
  exit 0
fi
exit 22
EOF
chmod +x "$mock_curl"

future_date() {
  local days="$1"
  if date -u -v+"${days}"d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -v+"${days}"d +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -d "+${days} days" +%Y-%m-%dT%H:%M:%SZ
  fi
}

safe_output="$work_dir/safe-output"
PATH="$work_dir/bin:$PATH" \
  VAULT_ADDR="https://openbao.example.invalid" \
  VAULT_TOKEN="must-not-be-printed" \
  AUDIT_EXPIRES="$(future_date 365)" \
  "$device_script" audit --warning-days 30 --inventory "$inventory" \
  >"$safe_output"
grep -q "device-a" "$safe_output"
grep -q "not-issued" "$safe_output"
! grep -q "must-not-be-printed" "$safe_output"

if PATH="$work_dir/bin:$PATH" \
  VAULT_ADDR="https://openbao.example.invalid" \
  VAULT_TOKEN="must-not-be-printed" \
  AUDIT_EXPIRES="$(future_date 1)" \
  "$device_script" audit --warning-days 30 --inventory "$inventory" \
  >/dev/null 2>&1; then
  echo "expected near-expiry audit to fail" >&2
  exit 1
fi

echo "Cloudflare mTLS inventory audit tests passed"
