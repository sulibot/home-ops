#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:${PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/terraform/infra/live/common/secrets.sops.yaml"
ASSET_DIR="${ASSET_DIR:-${REPO_ROOT}/tmp/pxe/routeros-usb/proxmox}"
ROUTEROS_DIR="${ROUTEROS_DIR:-usb1/proxmox}"
IPXE_EFI_URL="${IPXE_EFI_URL:-https://boot.ipxe.org/x86_64-efi/ipxe.efi}"
SNPONLY_EFI_URL="${SNPONLY_EFI_URL:-https://boot.ipxe.org/x86_64-efi/snponly.efi}"
REFRESH_BOOTLOADERS="${REFRESH_BOOTLOADERS:-0}"
ENABLE_BINARY_UPLOAD="${ENABLE_BINARY_UPLOAD:-0}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq
require_cmd sops
require_cmd yq

if [[ ! -d "${ASSET_DIR}" ]]; then
  echo "asset directory not found: ${ASSET_DIR}" >&2
  exit 1
fi

if [[ ! -f "${SECRETS_FILE}" ]]; then
  echo "secrets file not found: ${SECRETS_FILE}" >&2
  exit 1
fi

routeros_hosturl="$(sops -d "${SECRETS_FILE}" | yq -r '.routeros_hosturl')"
routeros_username="$(sops -d "${SECRETS_FILE}" | yq -r '.routeros_username')"
routeros_password="$(sops -d "${SECRETS_FILE}" | yq -r '.routeros_password')"

if [[ -z "${routeros_hosturl}" || -z "${routeros_username}" || -z "${routeros_password}" ]]; then
  echo "failed to load RouterOS credentials from ${SECRETS_FILE}" >&2
  exit 1
fi

api_get() {
  local path="$1"
  curl -sk --fail -u "${routeros_username}:${routeros_password}" \
    "${routeros_hosturl%/}/rest/${path}"
}

api_post() {
  local path="$1"
  local data="$2"
  curl -sk --fail -u "${routeros_username}:${routeros_password}" \
    -X POST "${routeros_hosturl%/}/rest/${path}" \
    -H "Content-Type: application/json" \
    --data "${data}"
}

api_post_file() {
  local path="$1"
  local payload_file="$2"
  curl -sk --fail -u "${routeros_username}:${routeros_password}" \
    -X POST "${routeros_hosturl%/}/rest/${path}" \
    -H "Content-Type: application/json" \
    --data-binary "@${payload_file}"
}

file_listing() {
  api_get "file"
}

tftp_listing() {
  api_get "ip/tftp"
}

ensure_bootloader() {
  local output_name="$1"
  local source_url="$2"
  local output_path="${ASSET_DIR}/${output_name}"

  if [[ "${REFRESH_BOOTLOADERS}" == "1" || ! -s "${output_path}" ]]; then
    curl -fsSL "${source_url}" -o "${output_path}"
    echo "downloaded ${output_name} from ${source_url}"
  fi
}

remote_file_exists() {
  local remote_name="$1"
  file_listing |
    jq -e --arg name "${remote_name}" '.[] | select(.name == $name)' >/dev/null
}

upsert_file() {
  local local_file="$1"
  local file_name
  file_name="$(basename "${local_file}")"
  local remote_name="${ROUTEROS_DIR}/${file_name}"
  local remote_id
  local payload_file

  remote_id="$(
    file_listing |
      jq -r --arg name "${remote_name}" '.[] | select(.name == $name) | .".id"' |
      head -n1
  )"

  payload_file="$(mktemp)"
  trap 'rm -f "${payload_file}"' RETURN

  if [[ -n "${remote_id}" ]]; then
    jq -Rs --arg id "${remote_id}" '{".id": $id, contents: .}' <"${local_file}" >"${payload_file}"
    api_post_file "file/set" "${payload_file}" >/dev/null
    echo "updated file ${remote_name}"
  else
    jq -Rs --arg name "${remote_name}" '{name: $name, contents: .}' <"${local_file}" >"${payload_file}"
    api_post_file "file/add" "${payload_file}" >/dev/null
    echo "created file ${remote_name}"
  fi

  rm -f "${payload_file}"
  trap - RETURN
}

remove_tftp_entry() {
  local entry_id="$1"
  api_post "ip/tftp/remove" "$(jq -nc --arg id "${entry_id}" '{".id": $id}')" >/dev/null
}

add_tftp_entry() {
  local req_filename="$1"
  local real_filename="$2"
  api_post "ip/tftp/add" "$(
    jq -nc \
      --arg req "${req_filename}" \
      --arg real "${real_filename}" \
      '{"req-filename": $req, "real-filename": $real, allow: "true", "read-only": "true", disabled: "false"}'
  )" >/dev/null
}

reconcile_tftp_entry() {
  local req_filename="$1"
  local real_filename="$2"
  local raw_entries
  raw_entries="$(tftp_listing)"

  local matching_ids
  matching_ids="$(
    jq -r \
      --arg req "${req_filename}" \
      --arg real "${real_filename}" \
      '.[] | select(."req-filename" == $req and ."real-filename" == $real and .disabled != "true") | .".id"' \
      <<<"${raw_entries}"
  )"

  local all_ids
  all_ids="$(
    jq -r --arg req "${req_filename}" '.[] | select(."req-filename" == $req) | .".id"' <<<"${raw_entries}"
  )"

  local keep_id=""
  if [[ -n "${matching_ids}" ]]; then
    keep_id="$(head -n1 <<<"${matching_ids}")"
  fi

  while IFS= read -r entry_id; do
    [[ -z "${entry_id}" ]] && continue
    if [[ -n "${keep_id}" && "${entry_id}" == "${keep_id}" ]]; then
      continue
    fi
    remove_tftp_entry "${entry_id}"
    echo "removed duplicate or stale tftp rule for ${req_filename}: ${entry_id}"
  done <<<"${all_ids}"

  if [[ -z "${keep_id}" ]]; then
    add_tftp_entry "${req_filename}" "${real_filename}"
    echo "created tftp rule ${req_filename} -> ${real_filename}"
  else
    echo "kept tftp rule ${req_filename} -> ${real_filename}"
  fi
}

echo "syncing RouterOS PXE assets from ${ASSET_DIR}"

mkdir -p "${ASSET_DIR}"
ensure_bootloader "ipxe.efi" "${IPXE_EFI_URL}"
ensure_bootloader "snponly.efi" "${SNPONLY_EFI_URL}"

mapfile -t generated_files < <(find "${ASSET_DIR}" -maxdepth 1 -type f \( -name '*.ipxe' -o -name 'host-profiles.json' \) | sort)

if [[ ${#generated_files[@]} -eq 0 ]]; then
  echo "no generated PXE assets found in ${ASSET_DIR}" >&2
  exit 1
fi

for file_path in "${generated_files[@]}"; do
  upsert_file "${file_path}"
done

if [[ "${ENABLE_BINARY_UPLOAD}" == "1" ]]; then
  upsert_file "${ASSET_DIR}/ipxe.efi"
  upsert_file "${ASSET_DIR}/snponly.efi"
else
  for bootloader in ipxe.efi snponly.efi; do
    if remote_file_exists "${ROUTEROS_DIR}/${bootloader}"; then
      echo "verified existing RouterOS bootloader ${ROUTEROS_DIR}/${bootloader}"
    else
      echo "missing RouterOS bootloader ${ROUTEROS_DIR}/${bootloader}; upload it out-of-band or enable a binary-capable management path" >&2
      exit 1
    fi
  done
fi

declare -A desired_tftp=(
  ["ipxe.efi"]="${ROUTEROS_DIR}/ipxe.efi"
  ["snponly.efi"]="${ROUTEROS_DIR}/snponly.efi"
  ["autoexec.ipxe"]="${ROUTEROS_DIR}/autoexec.ipxe"
  ["boot.ipxe"]="${ROUTEROS_DIR}/boot.ipxe"
)

for file_path in "${generated_files[@]}"; do
  base_name="$(basename "${file_path}")"
  if [[ "${base_name}" == *.ipxe ]]; then
    desired_tftp["${base_name}"]="${ROUTEROS_DIR}/${base_name}"
  fi
done

for req_filename in $(printf '%s\n' "${!desired_tftp[@]}" | sort); do
  reconcile_tftp_entry "${req_filename}" "${desired_tftp[${req_filename}]}"
done

echo "RouterOS PXE sync complete"
