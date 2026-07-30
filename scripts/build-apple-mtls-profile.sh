#!/usr/bin/env bash
# Build a device-specific Apple configuration profile containing a PKCS#12
# client identity. The caller owns secure delivery and cleanup of the result.
set -euo pipefail

umask 077

usage() {
  cat >&2 <<'EOF'
usage:
  build-apple-mtls-profile.sh \
    --platform {macos|ios|ipados} \
    --owner SLUG \
    --device SLUG \
    --certificate FILE \
    --private-key FILE \
    --password-file FILE \
    --output FILE

SLUG values may contain lowercase letters, numbers, dots, underscores, and
hyphens. The output contains a private identity and must be handled as a secret.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

xml_escape() {
  jq -Rr '@html' <<<"$1"
}

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:lower:]' '[:upper:]'
    return
  fi

  # Linux runners expose a kernel-generated UUID even when uuidgen is absent.
  [[ -r /proc/sys/kernel/random/uuid ]] ||
    die "uuidgen and /proc/sys/kernel/random/uuid are unavailable"
  tr '[:lower:]' '[:upper:]' </proc/sys/kernel/random/uuid
}

platform=""
owner=""
device=""
certificate_file=""
private_key_file=""
password_file=""
output_file=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --owner)
      owner="${2:-}"
      shift 2
      ;;
    --device)
      device="${2:-}"
      shift 2
      ;;
    --certificate)
      certificate_file="${2:-}"
      shift 2
      ;;
    --private-key)
      private_key_file="${2:-}"
      shift 2
      ;;
    --password-file)
      password_file="${2:-}"
      shift 2
      ;;
    --output)
      output_file="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

require_command openssl
require_command jq
require_command base64

case "$platform" in
  macos | ios | ipados) ;;
  *) die "--platform must be macos, ios, or ipados" ;;
esac

slug_pattern='^[a-z0-9][a-z0-9._-]{0,62}$'
[[ "$owner" =~ $slug_pattern ]] || die "invalid --owner slug"
[[ "$device" =~ $slug_pattern ]] || die "invalid --device slug"
[[ -f "$certificate_file" ]] || die "certificate file does not exist"
[[ -f "$private_key_file" ]] || die "private key file does not exist"
[[ -f "$password_file" ]] || die "password file does not exist"
[[ -n "$output_file" ]] || die "--output is required"
[[ ! -e "$output_file" ]] || die "refusing to overwrite existing output"
[[ -s "$password_file" ]] || die "password file is empty"

openssl x509 -in "$certificate_file" -noout >/dev/null 2>&1 ||
  die "certificate is not a valid PEM X.509 certificate"
openssl pkey -in "$private_key_file" -noout >/dev/null 2>&1 ||
  die "private key is not a valid PEM private key"

certificate_public_key="$(
  openssl x509 -in "$certificate_file" -pubkey -noout 2>/dev/null |
    openssl pkey -pubin -outform DER 2>/dev/null |
    openssl dgst -sha256
)"
private_public_key="$(
  openssl pkey -in "$private_key_file" -pubout -outform DER 2>/dev/null |
    openssl dgst -sha256
)"
[[ "$certificate_public_key" == "$private_public_key" ]] ||
  die "certificate and private key do not match"
unset certificate_public_key private_public_key

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/apple-mtls-profile.XXXXXX")"
cleanup() {
  if [[ -n "${work_dir:-}" && -d "$work_dir" ]]; then
    find "$work_dir" -type f -delete 2>/dev/null || true
    rmdir "$work_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT

identity_slug="${owner}-${device}"
display_name="Cloudflare mTLS - ${owner} - ${device}"
payload_identifier="com.sulibot.cloudflare-mtls.${identity_slug}"
identity_uuid="$(new_uuid)"
profile_uuid="$(new_uuid)"
p12_file="$work_dir/${identity_slug}.p12"

# OpenSSL 3 changed the PKCS#12 defaults to PBES2/AES. Apple can import those
# bundles directly into a keychain, but macOS and iOS reject them inside a
# configuration-profile PKCS#12 payload with an authentication error. Generate
# the legacy interoperable encoding used by Apple's Security framework. The
# profile is already a secret-bearing delivery artifact, so its security
# boundary is encrypted delivery/storage rather than the PKCS#12 wrapper.
pkcs12_compatibility_args=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
  pkcs12_compatibility_args=(-legacy)
else
  # Apple ships LibreSSL on older/current macOS releases; it has no -legacy
  # switch but supports the equivalent algorithms explicitly.
  pkcs12_compatibility_args=(
    -keypbe PBE-SHA1-3DES
    -certpbe PBE-SHA1-RC2-40
    -macalg sha1
  )
fi

openssl pkcs12 -export \
  "${pkcs12_compatibility_args[@]}" \
  -in "$certificate_file" \
  -inkey "$private_key_file" \
  -name "$display_name" \
  -passout "file:$password_file" \
  -out "$p12_file" >/dev/null 2>&1

p12_base64="$(base64 <"$p12_file" | tr -d '\r\n')"
password="$(<"$password_file")"
display_name_xml="$(xml_escape "$display_name")"
file_name_xml="$(xml_escape "${identity_slug}.p12")"
password_xml="$(xml_escape "$password")"
unset password

macos_private_key_controls=""
if [[ "$platform" == "macos" ]]; then
  macos_private_key_controls='
      <key>AllowAllAppsAccess</key>
      <true/>
      <key>KeyIsExtractable</key>
      <false/>'
fi

profile_tmp="$work_dir/profile.mobileconfig"
cat >"$profile_tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>${file_name_xml}</string>
      <key>PayloadContent</key>
      <data>${p12_base64}</data>
      <key>Password</key>
      <string>${password_xml}</string>${macos_private_key_controls}
      <key>PayloadDescription</key>
      <string>Cloudflare Application Security mTLS client identity</string>
      <key>PayloadDisplayName</key>
      <string>${display_name_xml}</string>
      <key>PayloadIdentifier</key>
      <string>${payload_identifier}.identity</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>${identity_uuid}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDescription</key>
  <string>Installs a client identity for sulibot.com Application Security mTLS.</string>
  <key>PayloadDisplayName</key>
  <string>${display_name_xml}</string>
  <key>PayloadIdentifier</key>
  <string>${payload_identifier}</string>
  <key>PayloadOrganization</key>
  <string>sulibot.com</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>${profile_uuid}</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$profile_tmp" >/dev/null
fi

install -m 0600 "$profile_tmp" "$output_file"
printf 'created %s profile: %s\n' "$platform" "$output_file"
