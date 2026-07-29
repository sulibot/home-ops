#!/usr/bin/env bash
set -euo pipefail

: "${COMMON_GID:?COMMON_GID is required}"
: "${USER_UID:?USER_UID is required}"
: "${USER_GID:?USER_GID is required}"

pve_client="${PVE_CLIENT:-10.200.0.205}"
ssh_key="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
vip="10.200.0.209"
ssh_opts=(-i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

ssh "${ssh_opts[@]}" "root@${pve_client}" \
  "VIP='${vip}' COMMON_GID='${COMMON_GID}' USER_UID='${USER_UID}' USER_GID='${USER_GID}' bash -s" <<'REMOTE'
set -euo pipefail
test_root="$(mktemp -d /mnt/nfs-gateway-test.XXXXXX)"
# The actual read/write probes drop privileges to the canonical POSIX identity.
# Let that identity traverse the temporary parent without granting directory
# listing or write access there.
chmod 0711 "${test_root}"
cleanup() {
  for test_dir in "${test_root}/personal" "${test_root}/common"; do
    if mountpoint -q "${test_dir}"; then
      umount "${test_dir}" 2>/dev/null || umount -l "${test_dir}" || true
    fi
  done
  rm -rf "${test_root:?}/personal" "${test_root:?}/common"
  rmdir "${test_root}" 2>/dev/null || true
}
trap cleanup EXIT

# OpenCloud owns the setgid Space tree as 1000:1000. The Kanidm UID is the NFS
# file owner; the service group and named ACL keep OpenCloud writable.
for export_spec in \
  "personal:/shared:${USER_UID}:1000" \
  "common:/common:${USER_UID}:${COMMON_GID}"; do
  IFS=: read -r name export_path uid gid <<<"${export_spec}"
  test_dir="${test_root}/${name}"
  install -d "${test_dir}"
  mount -t nfs4 -o vers=4.1,proto=tcp,hard,timeo=600,retrans=2 \
    "${VIP}:${export_path}" "${test_dir}"
  mountpoint -q "${test_dir}"

  test_file="${test_dir}/.nfs-gateway-validation"
  setpriv --reuid="${uid}" --regid="${gid}" --clear-groups sh -c \
    "printf 'validated %s %s\n' '${name}' \"\$(date -u +%FT%TZ)\" > '${test_file}'"
  test "$(setpriv --reuid="${uid}" --regid="${gid}" --clear-groups \
    stat -c '%u:%g' "${test_file}")" = "${uid}:${gid}"
  setpriv --reuid="${uid}" --regid="${gid}" --clear-groups cat "${test_file}"
  setpriv --reuid="${uid}" --regid="${gid}" --clear-groups rm -f "${test_file}"
done
REMOTE

for gateway in 10.200.0.207 10.200.0.208; do
  ssh "${ssh_opts[@]}" "root@${gateway}" '
    systemctl is-active --quiet keepalived
  '
done

owner_count=0
for gateway in 10.200.0.207 10.200.0.208; do
  if ssh "${ssh_opts[@]}" "root@${gateway}" \
    "ip -4 -o addr show dev eth0 | grep -q '${vip}/24'"; then
    ssh "${ssh_opts[@]}" "root@${gateway}" \
      'systemctl is-active --quiet nfs-ganesha; /usr/local/sbin/check-nfs-ganesha'
    owner_count=$((owner_count + 1))
  else
    ssh "${ssh_opts[@]}" "root@${gateway}" \
      '! systemctl is-active --quiet nfs-ganesha'
  fi
done
test "${owner_count}" -eq 1

printf 'NFSv4 validation succeeded through %s\n' "${vip}"
