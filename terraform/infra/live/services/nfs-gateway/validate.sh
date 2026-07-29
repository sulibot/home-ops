#!/usr/bin/env bash
set -euo pipefail

pve_client="${PVE_CLIENT:-10.200.0.206}"
ssh_key="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
vip="10.200.0.209"
ssh_opts=(-i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

ssh "${ssh_opts[@]}" "root@${pve_client}" "VIP='${vip}' bash -s" <<'REMOTE'
set -euo pipefail
test_dir="$(mktemp -d /mnt/nfs-gateway-test.XXXXXX)"
cleanup() {
  if mountpoint -q "${test_dir}"; then
    umount "${test_dir}" 2>/dev/null || umount -l "${test_dir}" || true
  fi
  rmdir "${test_dir}" 2>/dev/null || true
}
trap cleanup EXIT

mount -t nfs4 -o vers=4.1,proto=tcp,hard,timeo=600,retrans=2 "${VIP}:/shared" "${test_dir}"
mountpoint -q "${test_dir}"

test_file="${test_dir}/.nfs-gateway-validation"
setpriv --reuid=1000 --regid=1000 --clear-groups sh -c \
  "printf 'validated %s\n' \"\$(date -u +%FT%TZ)\" > '${test_file}'"
test "$(setpriv --reuid=1000 --regid=1000 --clear-groups \
  stat -c '%u:%g' "${test_file}")" = "1000:1000"
setpriv --reuid=1000 --regid=1000 --clear-groups cat "${test_file}"
setpriv --reuid=1000 --regid=1000 --clear-groups rm -f "${test_file}"
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
