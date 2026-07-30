#!/usr/bin/env bash
# List, audit, issue, export, or revoke Cloudflare-managed client identities.
# OpenBao is the source of truth. This script never writes identities to
# Terraform state or GitHub artifacts.
set -euo pipefail

umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
profile_builder="$script_dir/build-apple-mtls-profile.sh"
default_inventory="$repo_root/config/cloudflare-mtls-devices.json"
openbao_mount="${CLOUDFLARE_MTLS_OPENBAO_MOUNT:-kv}"
openbao_root="${CLOUDFLARE_MTLS_OPENBAO_ROOT:-automation/cloudflare-mtls}"

usage() {
  cat >&2 <<'EOF'
usage:
  cloudflare-mtls-device.sh list [--inventory FILE]

  cloudflare-mtls-device.sh audit \
    [--warning-days DAYS] [--inventory FILE]

  cloudflare-mtls-device.sh issue \
    --device-id ID \
    [--validity-days DAYS] [--output FILE] [--onepassword-vault VAULT]

  cloudflare-mtls-device.sh export \
    --device-id ID \
    [--output FILE] [--onepassword-vault VAULT]

  cloudflare-mtls-device.sh revoke --device-id ID

Device owner, platform, and certificate subject are derived from the committed
non-secret inventory at config/cloudflare-mtls-devices.json. Use --inventory
only for validation or development with a different inventory file.

Required environment:
  VAULT_ADDR and VAULT_TOKEN (or BAO_ADDR and BAO_TOKEN)

The OpenBao config secret at kv/automation/cloudflare-mtls/config contains:
  cloudflare_api_token
  cloudflare_zone_id
  onepassword_service_account_token
  onepassword_vault
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

openbao_request() {
  local method="$1"
  local path="$2"
  local data_file="${3:-}"
  local args=(
    --silent
    --show-error
    --fail-with-body
    --request "$method"
    --header "X-Vault-Token: $openbao_token"
  )

  if [[ -n "$data_file" ]]; then
    args+=(
      --header "Content-Type: application/json"
      --data-binary "@$data_file"
    )
  fi

  curl "${args[@]}" "${openbao_addr%/}/v1/$path"
}

read_openbao_secret() {
  local path="$1"
  openbao_request GET "$openbao_mount/data/$path"
}

write_openbao_secret() {
  local path="$1"
  local data_file="$2"
  openbao_request POST "$openbao_mount/data/$path" "$data_file" >/dev/null
}

load_cloudflare_config() {
  local config_response
  config_response="$(read_openbao_secret "$openbao_root/config")"
  cloudflare_api_token="$(
    jq -er '.data.data.cloudflare_api_token' <<<"$config_response"
  )"
  cloudflare_zone_id="$(
    jq -er '.data.data.cloudflare_zone_id' <<<"$config_response"
  )"
  unset config_response
}

load_onepassword_config() {
  local config_response configured_vault
  config_response="$(read_openbao_secret "$openbao_root/config")"
  OP_SERVICE_ACCOUNT_TOKEN="$(
    jq -er '.data.data.onepassword_service_account_token' <<<"$config_response"
  )"
  configured_vault="$(
    jq -er '.data.data.onepassword_vault // "Kubernetes"' <<<"$config_response"
  )"
  unset config_response

  if [[ -n "$onepassword_vault" ]] &&
    [[ "$onepassword_vault" != "$configured_vault" ]]; then
    die "requested 1Password vault does not match the OpenBao delivery configuration"
  fi
  onepassword_vault="$configured_vault"
  export OP_SERVICE_ACCOUNT_TOKEN
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::add-mask::%s\n' "$OP_SERVICE_ACCOUNT_TOKEN"
  fi
}

validate_slug() {
  local label="$1"
  local value="$2"
  local slug_pattern='^[a-z0-9][a-z0-9._-]{0,62}$'
  [[ "$value" =~ $slug_pattern ]] || die "invalid $label slug"
}

load_inventory_device() {
  local inventory_entry
  [[ -f "$inventory_file" ]] || die "device inventory not found: $inventory_file"
  jq -e '
    .schema_version == 1 and
    (.devices | type == "array") and
    ([.devices[].id] | length == (unique | length))
  ' "$inventory_file" >/dev/null || die "device inventory is invalid"

  inventory_entry="$(
    jq -cer --arg id "$device_id" '
      .devices[] | select(.id == $id)
    ' "$inventory_file"
  )" || die "unknown device ID: $device_id"

  display_name="$(jq -er '.display_name' <<<"$inventory_entry")"
  owner="$(jq -er '.owner' <<<"$inventory_entry")"
  device="$(jq -er '.device' <<<"$inventory_entry")"
  platform="$(jq -er '.platform' <<<"$inventory_entry")"
  validate_slug "device ID" "$device_id"
  validate_slug owner "$owner"
  validate_slug device "$device"
  case "$platform" in
    macos | ios | ipados) ;;
    *) die "unsupported platform in inventory for $device_id" ;;
  esac
}

device_path() {
  printf '%s/identities/%s/current' "$openbao_root" "$device_id"
}

inventory_path() {
  printf '%s/inventory/%s/current' "$openbao_root" "$device_id"
}

deliver_profile() {
  local profile_file="$1"
  local profile_name="$2"
  local certificate_id="$3"
  local document_title existing_items matching_items match_count
  local existing_id existing_profile

  if [[ -n "$output_file" ]]; then
    [[ ! -e "$output_file" ]] || die "refusing to overwrite existing output"
    install -m 0600 "$profile_file" "$output_file"
    printf 'wrote local installation copy: %s\n' "$output_file"
  fi

  if [[ -n "$onepassword_vault" ]]; then
    require_command op
    require_command cmp
    document_title="Cloudflare mTLS - ${device_id} - ${certificate_id}"
    existing_items="$(
      op item list --vault "$onepassword_vault" --format=json
    )"
    matching_items="$(
      jq -c --arg title "$document_title" \
        '[.[] | select(.title == $title)]' <<<"$existing_items"
    )"
    unset existing_items
    match_count="$(jq -r 'length' <<<"$matching_items")"
    if ((match_count > 1)); then
      die "multiple 1Password documents have the expected title: $document_title"
    fi
    if ((match_count == 1)); then
      existing_id="$(jq -er '.[0].id' <<<"$matching_items")"
      existing_profile="${profile_file}.onepassword-existing"
      op document get "$existing_id" \
        --vault "$onepassword_vault" \
        --out-file "$existing_profile" >/dev/null
      if ! cmp -s "$profile_file" "$existing_profile"; then
        die "1Password document exists but its contents differ: $document_title"
      fi
      find "$existing_profile" -type f -delete
      printf '1Password document already current in vault: %s\n' \
        "$onepassword_vault"
      unset OP_SERVICE_ACCOUNT_TOKEN
      return
    fi

    op document create "$profile_file" \
      --title "$document_title" \
      --file-name "$profile_name" \
      --tags "cloudflare,mtls,client-certificate" \
      --vault "$onepassword_vault" >/dev/null
    printf 'created 1Password document in vault: %s\n' "$onepassword_vault"
    unset OP_SERVICE_ACCOUNT_TOKEN
  fi
}

action="${1:-}"
[[ -n "$action" ]] || {
  usage
  exit 2
}
shift

device_id=""
owner=""
device=""
platform=""
display_name=""
validity_days="365"
warning_days="30"
output_file=""
onepassword_vault=""
inventory_file="$default_inventory"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --device-id)
      device_id="${2:-}"
      shift 2
      ;;
    --validity-days)
      validity_days="${2:-}"
      shift 2
      ;;
    --warning-days)
      warning_days="${2:-}"
      shift 2
      ;;
    --output)
      output_file="${2:-}"
      shift 2
      ;;
    --onepassword-vault)
      onepassword_vault="${2:-}"
      shift 2
      ;;
    --inventory)
      inventory_file="${2:-}"
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

require_command jq

if [[ "$action" == "list" ]]; then
  [[ -f "$inventory_file" ]] || die "device inventory not found: $inventory_file"
  jq -e '
    .schema_version == 1 and
    (.devices | type == "array") and
    ([.devices[].id] | length == (unique | length))
  ' "$inventory_file" >/dev/null || die "device inventory is invalid"
  jq -r '
    ["DEVICE ID", "OWNER", "PLATFORM", "DISPLAY NAME"],
    (.devices[] | [.id, .owner, .platform, .display_name]) |
    @tsv
  ' "$inventory_file" |
    column -t -s $'\t'
  exit 0
fi

require_command curl
openbao_addr="${VAULT_ADDR:-${BAO_ADDR:-}}"
openbao_token="${VAULT_TOKEN:-${BAO_TOKEN:-}}"
[[ -n "$openbao_addr" ]] || die "VAULT_ADDR or BAO_ADDR is required"
[[ -n "$openbao_token" ]] || die "VAULT_TOKEN or BAO_TOKEN is required"

if [[ "$action" == "audit" ]]; then
  [[ "$warning_days" =~ ^[0-9]+$ ]] ||
    die "--warning-days must be a non-negative integer"
  [[ -f "$inventory_file" ]] || die "device inventory not found: $inventory_file"
  jq -e '
    .schema_version == 1 and
    (.devices | type == "array") and
    ([.devices[].id] | length == (unique | length))
  ' "$inventory_file" >/dev/null || die "device inventory is invalid"

  printf '%-24s %-10s %-7s %s\n' "DEVICE ID" "STATUS" "DAYS" "EXPIRES"
  audit_failed=false
  while IFS= read -r audit_device_id; do
    audit_path="$openbao_root/inventory/$audit_device_id/current"
    if ! audit_response="$(read_openbao_secret "$audit_path" 2>/dev/null)"; then
      printf '%-24s %-10s %-7s %s\n' "$audit_device_id" "not-issued" "-" "-"
      if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        printf '::warning title=mTLS identity not issued::%s has no current identity in OpenBao\n' \
          "$audit_device_id"
      fi
      continue
    fi

    audit_status="$(jq -er '.data.data.status' <<<"$audit_response")"
    audit_expires="$(jq -er '.data.data.expires_on' <<<"$audit_response")"
    audit_expiry_epoch="$(
      jq -nr --arg value "$audit_expires" \
        '$value | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601'
    )"
    audit_now_epoch="$(date +%s)"
    audit_days="$(((audit_expiry_epoch - audit_now_epoch) / 86400))"
    printf '%-24s %-10s %-7s %s\n' \
      "$audit_device_id" "$audit_status" "$audit_days" "$audit_expires"

    if [[ "$audit_status" == "active" ]] && ((audit_days <= warning_days)); then
      audit_failed=true
      if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        printf '::error title=mTLS identity rotation required::%s expires in %s days (%s)\n' \
          "$audit_device_id" "$audit_days" "$audit_expires"
      fi
    elif [[ "$audit_status" != "active" ]] &&
      [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      printf '::warning title=mTLS identity inactive::%s status is %s\n' \
        "$audit_device_id" "$audit_status"
    fi
    unset audit_response
  done < <(jq -r '.devices[].id' "$inventory_file")

  if [[ "$audit_failed" == "true" ]]; then
    die "one or more active identities expire within $warning_days days"
  fi
  exit 0
fi

[[ -n "$device_id" ]] || die "--device-id is required"
load_inventory_device
require_command openssl
require_command base64
[[ -x "$profile_builder" ]] || die "profile builder is not executable"

identity_slug="${owner}-${device}"
current_path="$(device_path)"
current_inventory_path="$(inventory_path)"

case "$action" in
  issue)
    [[ "$validity_days" =~ ^[0-9]+$ ]] ||
      die "--validity-days must be a positive integer"
    ((validity_days > 0)) || die "--validity-days must be greater than zero"

    if current_response="$(read_openbao_secret "$current_path" 2>/dev/null)"; then
      current_status="$(jq -er '.data.data.status' <<<"$current_response")"
      unset current_response
      if [[ "$current_status" != "revoked" ]]; then
        die "an active identity already exists for $device_id; revoke it first"
      fi
    fi

    if [[ -n "$onepassword_vault" ]]; then
      require_command op
      load_onepassword_config
    fi
    load_cloudflare_config
    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/cloudflare-mtls-device.XXXXXX")"
    certificate_id=""
    certificate_committed=false
    cleanup() {
      if [[ -n "$certificate_id" ]] &&
        [[ "$certificate_committed" != "true" ]] &&
        [[ -n "${cloudflare_api_token:-}" ]]; then
        # Any failure after signing but before durable OpenBao storage must not
        # leave a valid certificate whose private key may have been destroyed.
        curl --silent --show-error \
          --request DELETE \
          --header "Authorization: Bearer $cloudflare_api_token" \
          "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone_id/client_certificates/$certificate_id" \
          >/dev/null 2>&1 || true
      fi
      if [[ -n "${work_dir:-}" && -d "$work_dir" ]]; then
        find "$work_dir" -type f -delete 2>/dev/null || true
        rmdir "$work_dir" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

    private_key_file="$work_dir/private-key.pem"
    csr_file="$work_dir/request.csr"
    certificate_file="$work_dir/certificate.pem"
    password_file="$work_dir/p12-password"
    profile_file="$work_dir/${identity_slug}-${platform}.mobileconfig"
    api_request_file="$work_dir/cloudflare-request.json"
    api_response_file="$work_dir/cloudflare-response.json"
    openbao_payload_file="$work_dir/openbao-payload.json"
    openbao_metadata_file="$work_dir/openbao-metadata.json"

    # Match Cloudflare's documented client-certificate CSR example and retain
    # broad compatibility with Apple certificate consumers.
    openssl genpkey \
      -algorithm RSA \
      -pkeyopt rsa_keygen_bits:2048 \
      -out "$private_key_file" 2>/dev/null
    openssl req -new \
      -key "$private_key_file" \
      -out "$csr_file" \
      -subj "/O=sulibot.com/OU=Application Security mTLS/CN=$identity_slug"
    openssl rand -hex 32 >"$password_file"

    jq -n \
      --rawfile csr "$csr_file" \
      --argjson validity_days "$validity_days" \
      '{csr:$csr,validity_days:$validity_days}' >"$api_request_file"

    curl --silent --show-error --fail-with-body \
      --request POST \
      --header 'Content-Type: application/json' \
      --header "Authorization: Bearer $cloudflare_api_token" \
      --data-binary "@$api_request_file" \
      "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone_id/client_certificates" \
      >"$api_response_file"

    jq -e '.success == true and (.result.id | length > 0)' \
      "$api_response_file" >/dev/null ||
      die "Cloudflare did not return a client certificate"
    certificate_id="$(jq -er '.result.id' "$api_response_file")"
    jq -er '.result.certificate' "$api_response_file" >"$certificate_file"

    "$profile_builder" \
      --platform "$platform" \
      --owner "$owner" \
      --device "$device" \
      --certificate "$certificate_file" \
      --private-key "$private_key_file" \
      --password-file "$password_file" \
      --output "$profile_file" >/dev/null

    generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -n \
      --arg owner "$owner" \
      --arg device "$device" \
      --arg device_id "$device_id" \
      --arg display_name "$display_name" \
      --arg platform "$platform" \
      --arg generated_at "$generated_at" \
      --arg profile_file_name "$(basename "$profile_file")" \
      --arg profile_identifier "com.sulibot.cloudflare-mtls.${identity_slug}" \
      --arg cloudflare_zone_id "$cloudflare_zone_id" \
      --rawfile private_key_pem "$private_key_file" \
      --rawfile certificate_pem "$certificate_file" \
      --rawfile pkcs12_password "$password_file" \
      --rawfile cloudflare "$api_response_file" \
      --rawfile mobileconfig "$profile_file" \
      '{
        data: {
          schema_version: 1,
          device_id: $device_id,
          display_name: $display_name,
          owner: $owner,
          device: $device,
          platform: $platform,
          generated_at: $generated_at,
          profile_file_name: $profile_file_name,
          profile_identifier: $profile_identifier,
          cloudflare_zone_id: $cloudflare_zone_id,
          cloudflare_certificate_id: ($cloudflare | fromjson | .result.id),
          certificate_authority_id:
            ($cloudflare | fromjson | .result.certificate_authority.id),
          certificate_authority_name:
            ($cloudflare | fromjson | .result.certificate_authority.name),
          serial_number: ($cloudflare | fromjson | .result.serial_number),
          fingerprint_sha256:
            ($cloudflare | fromjson | .result.fingerprint_sha256),
          issued_on: ($cloudflare | fromjson | .result.issued_on),
          expires_on: ($cloudflare | fromjson | .result.expires_on),
          validity_days: ($cloudflare | fromjson | .result.validity_days),
          status: ($cloudflare | fromjson | .result.status),
          certificate_pem: $certificate_pem,
          private_key_pem: $private_key_pem,
          pkcs12_password: ($pkcs12_password | rtrimstr("\n")),
          mobileconfig_base64: ($mobileconfig | @base64)
        }
      }' >"$openbao_payload_file"

    jq '{
      data: (
        .data |
        del(
          .certificate_pem,
          .private_key_pem,
          .pkcs12_password,
          .mobileconfig_base64
        )
      )
    }' "$openbao_payload_file" >"$openbao_metadata_file"

    version_path="$openbao_root/identities/$device_id/versions/$certificate_id"
    metadata_version_path="$openbao_root/inventory/$device_id/versions/$certificate_id"
    if ! write_openbao_secret "$version_path" "$openbao_payload_file" ||
      ! write_openbao_secret "$current_path" "$openbao_payload_file" ||
      ! write_openbao_secret "$metadata_version_path" "$openbao_metadata_file" ||
      ! write_openbao_secret "$current_inventory_path" "$openbao_metadata_file"; then
      die "OpenBao storage failed; automatic Cloudflare revocation was requested"
    fi
    certificate_committed=true
    unset cloudflare_api_token

    deliver_profile "$profile_file" "$(basename "$profile_file")" "$certificate_id"
    printf 'issued Cloudflare client identity for: %s\n' "$device_id"
    printf 'OpenBao path: %s/%s\n' "$openbao_mount" "$current_path"
    printf 'Cloudflare certificate ID: %s\n' "$certificate_id"
    printf 'expires: %s\n' "$(jq -er '.result.expires_on' "$api_response_file")"
    ;;

  export)
    [[ -n "$output_file" || -n "$onepassword_vault" ]] ||
      die "export requires --output or --onepassword-vault"
    response="$(read_openbao_secret "$current_path")"
    current_status="$(jq -er '.data.data.status' <<<"$response")"
    [[ "$current_status" == "active" ]] ||
      die "refusing to export an identity with status: $current_status"
    if [[ -n "$onepassword_vault" ]]; then
      require_command op
      load_onepassword_config
    fi
    certificate_id="$(
      jq -er '.data.data.cloudflare_certificate_id' <<<"$response"
    )"
    profile_name="$(
      jq -er '.data.data.profile_file_name' <<<"$response"
    )"
    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/cloudflare-mtls-export.XXXXXX")"
    cleanup() {
      if [[ -n "${work_dir:-}" && -d "$work_dir" ]]; then
        find "$work_dir" -type f -delete 2>/dev/null || true
        rmdir "$work_dir" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT
    profile_file="$work_dir/$profile_name"
    encoded_profile="$(
      jq -er '.data.data.mobileconfig_base64' <<<"$response"
    )"
    if base64 --help 2>&1 | grep -q -- '--decode'; then
      printf '%s' "$encoded_profile" | base64 --decode >"$profile_file"
    else
      printf '%s' "$encoded_profile" | base64 -D >"$profile_file"
    fi
    unset encoded_profile
    unset response
    chmod 0600 "$profile_file"
    deliver_profile "$profile_file" "$profile_name" "$certificate_id"
    ;;

  revoke)
    load_cloudflare_config
    response="$(read_openbao_secret "$current_path")"
    current_status="$(jq -er '.data.data.status' <<<"$response")"
    [[ "$current_status" != "revoked" ]] ||
      die "identity is already revoked: $device_id"
    certificate_id="$(
      jq -er '.data.data.cloudflare_certificate_id' <<<"$response"
    )"

    curl --silent --show-error --fail-with-body \
      --request DELETE \
      --header "Authorization: Bearer $cloudflare_api_token" \
      "https://api.cloudflare.com/client/v4/zones/$cloudflare_zone_id/client_certificates/$certificate_id" \
      | jq -e '.success == true' >/dev/null
    unset cloudflare_api_token

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/cloudflare-mtls-revoke.XXXXXX")"
    cleanup() {
      if [[ -n "${work_dir:-}" && -d "$work_dir" ]]; then
        find "$work_dir" -type f -delete 2>/dev/null || true
        rmdir "$work_dir" 2>/dev/null || true
      fi
    }
    trap cleanup EXIT
    openbao_payload_file="$work_dir/openbao-payload.json"
    openbao_metadata_file="$work_dir/openbao-metadata.json"
    jq '{
      data: (
        .data.data +
        {
          status: "revoked",
          revoked_at: (now | todateiso8601)
        }
      )
    }' <<<"$response" >"$openbao_payload_file"
    unset response
    jq '{
      data: (
        .data |
        del(
          .certificate_pem,
          .private_key_pem,
          .pkcs12_password,
          .mobileconfig_base64
        )
      )
    }' "$openbao_payload_file" >"$openbao_metadata_file"
    version_path="$openbao_root/identities/$device_id/versions/$certificate_id"
    metadata_version_path="$openbao_root/inventory/$device_id/versions/$certificate_id"
    write_openbao_secret "$version_path" "$openbao_payload_file"
    write_openbao_secret "$current_path" "$openbao_payload_file"
    write_openbao_secret "$metadata_version_path" "$openbao_metadata_file"
    write_openbao_secret "$current_inventory_path" "$openbao_metadata_file"
    printf 'revoked Cloudflare client identity for: %s\n' "$device_id"
    ;;

  *)
    usage
    die "action must be list, audit, issue, export, or revoke"
    ;;
esac
