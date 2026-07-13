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
PVE_NODE="${PVE_NODE:-pve01}"

# Download directly on the PVE node into the shared template store: the PVE
# upload API rejects/ignores some multipart vztmpl uploads, and the node has
# a faster pipe anyway. mgmt IP from site.json.
PVE_HOST="$(python3 -c "import json; print(json.load(open('${REPO_ROOT}/site.json'))['proxmox']['nodes']['${PVE_NODE}']['mgmt_ip'])")"
TEMPLATE_DIR="$(ssh "root@${PVE_HOST}" "pvesm path 'resources:vztmpl/${TARGET_NAME}' 2>/dev/null | xargs dirname || echo /mnt/pve/resources/template/cache")"

echo "Downloading NixOS ${RELEASE} proxmoxLXC tarball on ${PVE_NODE} (${PVE_HOST})..."
ssh "root@${PVE_HOST}" "curl -fsSL --retry 3 -o '${TEMPLATE_DIR}/${TARGET_NAME}' '${HYDRA_URL}'"
ssh "root@${PVE_HOST}" "pvesm list resources --content vztmpl | grep -F '${TARGET_NAME}'"
echo "✓ Template available: resources:vztmpl/${TARGET_NAME}"
