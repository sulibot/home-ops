#!/usr/bin/env bash
# Download the latest NixOS proxmoxLXC template tarball from Hydra and
# upload it to the Proxmox 'resources' datastore as
#   resources:vztmpl/nixos-25.11-proxmox-lxc-x86_64.tar.xz
# (the file_id referenced by live/services/nixtest-lxc).
set -euo pipefail

RELEASE="${NIXOS_RELEASE:-25.11}"
HYDRA_URL="https://hydra.nixos.org/job/nixos/release-${RELEASE}/nixos.proxmoxLXC.x86_64-linux/latest/download-by-type/file/system-tarball"
TARGET_NAME="nixos-${RELEASE}-proxmox-lxc-x86_64.tar.xz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/terraform/infra/live/common/secrets.sops.yaml"

PVE_ENDPOINT="$(sops -d "${SECRETS_FILE}" | yq -r '.pve_endpoint')"
PVE_PASSWORD="$(sops -d "${SECRETS_FILE}" | yq -r '.pve_password')"
PVE_NODE="${PVE_NODE:-pve01}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "Downloading NixOS ${RELEASE} proxmoxLXC tarball from Hydra..."
curl -fL --retry 3 -o "${WORKDIR}/${TARGET_NAME}" "${HYDRA_URL}"
echo "Downloaded: $(du -h "${WORKDIR}/${TARGET_NAME}" | cut -f1)"

echo "Authenticating to Proxmox..."
AUTH="$(curl -sk -d "username=root@pam" --data-urlencode "password=${PVE_PASSWORD}" "${PVE_ENDPOINT}/access/ticket")"
TICKET="$(printf '%s' "${AUTH}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["ticket"])')"
CSRF="$(printf '%s' "${AUTH}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["CSRFPreventionToken"])')"

echo "Uploading to ${PVE_NODE} resources:vztmpl/${TARGET_NAME}..."
curl -fk -X POST \
  -b "PVEAuthCookie=${TICKET}" \
  -H "CSRFPreventionToken: ${CSRF}" \
  -F "content=vztmpl" \
  -F "filename=@${WORKDIR}/${TARGET_NAME}" \
  "${PVE_ENDPOINT}/nodes/${PVE_NODE}/storage/resources/upload"

echo
echo "✓ Template uploaded: resources:vztmpl/${TARGET_NAME}"
