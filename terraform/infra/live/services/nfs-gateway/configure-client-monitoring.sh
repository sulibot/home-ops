#!/bin/bash
# Reconcile the always-on VM that supplies the user-facing NFS availability SLI.
set -euo pipefail

client="${NFS_MONITOR_CLIENT:-10.200.0.205}"
common_gid="${COMMON_GID:-1965604563}"
user_uid="${USER_UID:-1888405477}"
user_gid="${USER_GID:-1888405477}"
ssh_key="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ssh_opts=(
  -i "${ssh_key}"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

ssh "${ssh_opts[@]}" "root@${client}" \
  'install -m 0750 /dev/stdin /usr/local/sbin/nfs-client-monitoring-provision' \
  <"${script_dir}/provision-client-monitoring.sh"
ssh "${ssh_opts[@]}" "root@${client}" \
  "COMMON_GID='${common_gid}' USER_UID='${user_uid}' USER_GID='${user_gid}' /usr/local/sbin/nfs-client-monitoring-provision"
