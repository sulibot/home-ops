#!/usr/bin/env bash
set -euo pipefail

umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
builder="$repo_root/scripts/build-apple-mtls-profile.sh"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/test-apple-mtls-profile.XXXXXX")"

cleanup() {
  if [[ -d "$work_dir" ]]; then
    find "$work_dir" -type f -delete 2>/dev/null || true
    rmdir "$work_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

key_file="$work_dir/key.pem"
wrong_key_file="$work_dir/wrong-key.pem"
cert_file="$work_dir/cert.pem"
password_file="$work_dir/password"
macos_profile="$work_dir/macos.mobileconfig"
ios_profile="$work_dir/ios.mobileconfig"

openssl ecparam -name prime256v1 -genkey -noout -out "$key_file"
openssl ecparam -name prime256v1 -genkey -noout -out "$wrong_key_file"
openssl req -new -x509 -days 1 \
  -key "$key_file" \
  -out "$cert_file" \
  -subj '/O=sulibot.com/CN=test-device'
printf '%s\n' 'test-only-password' >"$password_file"

"$builder" \
  --platform macos \
  --owner test \
  --device mac \
  --certificate "$cert_file" \
  --private-key "$key_file" \
  --password-file "$password_file" \
  --output "$macos_profile" >/dev/null

"$builder" \
  --platform ios \
  --owner test \
  --device iphone \
  --certificate "$cert_file" \
  --private-key "$key_file" \
  --password-file "$password_file" \
  --output "$ios_profile" >/dev/null

grep -q '<key>AllowAllAppsAccess</key>' "$macos_profile"
grep -q '<key>KeyIsExtractable</key>' "$macos_profile"
if grep -q '<key>AllowAllAppsAccess</key>' "$ios_profile"; then
  echo "iOS profile unexpectedly contains AllowAllAppsAccess" >&2
  exit 1
fi
if grep -q '<key>KeyIsExtractable</key>' "$ios_profile"; then
  echo "iOS profile unexpectedly contains KeyIsExtractable" >&2
  exit 1
fi

[[ "$(stat -f '%Lp' "$macos_profile" 2>/dev/null || stat -c '%a' "$macos_profile")" == "600" ]]
[[ "$(stat -f '%Lp' "$ios_profile" 2>/dev/null || stat -c '%a' "$ios_profile")" == "600" ]]

if "$builder" \
  --platform macos \
  --owner test \
  --device wrong-key \
  --certificate "$cert_file" \
  --private-key "$wrong_key_file" \
  --password-file "$password_file" \
  --output "$work_dir/should-not-exist.mobileconfig" >/dev/null 2>&1; then
  echo "builder accepted a mismatched private key" >&2
  exit 1
fi

printf 'Apple mTLS profile tests passed\n'
