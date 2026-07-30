#!/usr/bin/env bash
# Reconcile two host bind mounts after an LXC apply. The Proxmox provider can
# create a container with only mp0 even when multiple mount_point blocks are
# present in the create request. A later refresh sees the missing block as a
# force-replacement change, so make the intended PVE configuration explicit
# immediately after creation.
set -euo pipefail

if [[ $# -ne 8 ]]; then
  echo "usage: $0 <node> <vmid> <personal-source> <personal-target> <common-source> <common-target> <user-uid> <user-gid>" >&2
  exit 2
fi

node="$1"
vmid="$2"
personal_source="$3"
personal_target="$4"
common_source="$5"
common_target="$6"
user_uid="$7"
user_gid="$8"

[[ "${node}" =~ ^[a-zA-Z0-9.-]+$ ]]
[[ "${vmid}" =~ ^[0-9]+$ ]]
[[ "${user_uid}" =~ ^[0-9]+$ ]]
[[ "${user_gid}" =~ ^[0-9]+$ ]]

for path in "${personal_source}" "${personal_target}" "${common_source}" "${common_target}"; do
  [[ "${path}" =~ ^/[a-zA-Z0-9._/-]+$ ]]
done

ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  "root@${node}" bash -s -- \
  "${vmid}" "${personal_source}" "${personal_target}" "${common_source}" "${common_target}" \
  "${user_uid}" "${user_gid}" <<'REMOTE'
set -euo pipefail

vmid="$1"
personal_source="$2"
personal_target="$3"
common_source="$4"
common_target="$5"
user_uid="$6"
user_gid="$7"
personal_parent="${personal_target%/*}"

pct set "${vmid}" \
  -mp0 "${personal_source},mp=${personal_target},backup=0,replicate=0,shared=1"
pct set "${vmid}" \
  -mp1 "${common_source},mp=${common_target},backup=0,replicate=0,shared=1"

pct config "${vmid}" | grep -F \
  "mp0: ${personal_source},mp=${personal_target}"
pct config "${vmid}" | grep -F \
  "mp1: ${common_source},mp=${common_target}"
pct exec "${vmid}" -- sh -lc \
  "chown ${user_uid}:${user_gid} '${personal_parent}' && chmod 0700 '${personal_parent}'"
REMOTE
