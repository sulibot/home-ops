#!/bin/bash
# Reconcile the always-on VM that supplies the user-facing NFS availability SLI.
set -euo pipefail

client="${NFS_MONITOR_CLIENT:-10.200.0.205}"
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
  '/usr/local/sbin/nfs-client-monitoring-provision'
