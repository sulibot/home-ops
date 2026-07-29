#!/usr/bin/env bash
# Create least-privilege Ceph identities and install their keyrings without
# placing secrets in Terraform state or the repository.
set -euo pipefail

: "${COMMON_SPACE_ID:?COMMON_SPACE_ID is required}"
: "${COMMON_GID:?COMMON_GID is required}"
: "${USER_UID:?USER_UID is required}"
: "${USER_GID:?USER_GID is required}"

pve_host="${PVE_HOST:-10.10.0.1}"
ssh_key="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
gateways=(10.200.0.207 10.200.0.208)
ssh_opts=(-i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

ssh "${ssh_opts[@]}" "root@${pve_host}" \
  "COMMON_SPACE_ID='${COMMON_SPACE_ID}' COMMON_GID='${COMMON_GID}' USER_UID='${USER_UID}' USER_GID='${USER_GID}' bash -s" <<'REMOTE'
  set -eu
  cloud_path=/mnt/pve/content/users/sulibot/Cloud
  common_path="/mnt/pve/content/users/projects/${COMMON_SPACE_ID}"
  if [ ! -d "${cloud_path}" ]; then
    echo "OpenCloud must initialize ${cloud_path} before the export is configured" >&2
    exit 1
  fi
  test -d "${common_path}"
  # OpenCloud must create and own the personal Space root so its immutable
  # Space metadata is present. Kanidm's canonical UID/GID receives an ACL;
  # never pre-create or replace this directory.
  chown "1000:1000" "${cloud_path}"
  # Root_Squash maps the kernel mount lookup to the anonymous identity. Grant
  # traverse-only access so clients can mount the export; write access remains
  # controlled by the canonical POSIX ACL and file modes.
  chmod 2751 "${cloud_path}"
  setfacl -m u:1000:rwx,u:"${USER_UID}":rwx,g:"${USER_GID}":rwx,m:rwx \
    -m d:u:"${USER_UID}":rwx,d:u:1000:rwx,d:g:"${USER_GID}":rwx,d:m:rwx,d:o:--- \
    "${cloud_path}"
  chown "1000:${COMMON_GID}" "${common_path}"
  # The anonymous Root_Squash identity needs traverse-only permission for the
  # mount lookup. It cannot list or read content; the caller's canonical UID
  # and GID authorize operations after the mount is established.
  chmod 2771 "${common_path}"
  setfacl -m u:1000:rwx,g:"${COMMON_GID}":rwx,m:rwx,o:--x \
    -m d:u:1000:rwx,d:g:"${COMMON_GID}":rwx,d:m:rwx,d:o:--- \
    "${common_path}"
  if ! ceph osd pool ls | grep -qx "nfs-ganesha"; then
    ceph osd pool create nfs-ganesha 16
  fi
  ceph osd pool application enable nfs-ganesha nfs
  ceph auth get-or-create client.nfs-shared \
    mon "allow r fsname=content" \
    mds "allow rw fsname=content path=/users/sulibot/Cloud" \
    osd "allow rw tag cephfs data=content" >/dev/null
  ceph auth get-or-create client.nfs-common \
    mon "allow r fsname=content" \
    mds "allow rw fsname=content path=/users/projects/${COMMON_SPACE_ID}" \
    osd "allow rw tag cephfs data=content" >/dev/null
  ceph auth get-or-create client.nfs-recovery \
    mon "allow r" \
    osd "allow rw pool=nfs-ganesha" >/dev/null
REMOTE

for gateway in "${gateways[@]}"; do
  ssh "${ssh_opts[@]}" "root@${pve_host}" \
    'printf "[global]\nfsid = %s\nmon_host = %s\nauth_client_required = cephx\nms_bind_ipv4 = false\nms_bind_ipv6 = true\n\n" "$(ceph fsid)" "$(awk -F"=" "/^[[:space:]]*mon_host[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, \"\", \$2); print \$2; exit}" /etc/pve/ceph.conf)"; printf "[client.nfs-shared]\nkeyring = /etc/ceph/ceph.client.nfs-shared.keyring\n\n[client.nfs-common]\nkeyring = /etc/ceph/ceph.client.nfs-common.keyring\n\n[client.nfs-recovery]\nkeyring = /etc/ceph/ceph.client.nfs-recovery.keyring\n"' |
    ssh "${ssh_opts[@]}" "root@${gateway}" \
      'umask 077; install -m 0600 /dev/stdin /etc/ceph/ceph.conf'

  ssh "${ssh_opts[@]}" "root@${pve_host}" \
    'ceph auth get client.nfs-shared' |
    ssh "${ssh_opts[@]}" "root@${gateway}" \
      'umask 077; install -m 0600 /dev/stdin /etc/ceph/ceph.client.nfs-shared.keyring'

  ssh "${ssh_opts[@]}" "root@${pve_host}" \
    'ceph auth get client.nfs-common' |
    ssh "${ssh_opts[@]}" "root@${gateway}" \
      'umask 077; install -m 0600 /dev/stdin /etc/ceph/ceph.client.nfs-common.keyring'

  ssh "${ssh_opts[@]}" "root@${pve_host}" \
    'ceph auth get client.nfs-recovery' |
    ssh "${ssh_opts[@]}" "root@${gateway}" \
      'umask 077; install -m 0600 /dev/stdin /etc/ceph/ceph.client.nfs-recovery.keyring'
done

for gateway in "${gateways[@]}"; do
  ssh "${ssh_opts[@]}" "root@${gateway}" \
    'systemctl stop keepalived;
     systemctl kill --kill-whom=main --signal=KILL nfs-ganesha 2>/dev/null || true;
     systemctl reset-failed nfs-ganesha 2>/dev/null || true;
     rm -f /run/nfs-gateway-inhibit /run/nfs-gateway-health-failures \
       /run/nfs-gateway-starting'
done

# Start the preferred owner first. Its promotion callback starts the one active
# Ganesha daemon. The peer then joins as a warm Keepalived standby.
ssh "${ssh_opts[@]}" "root@${gateways[0]}" 'systemctl start keepalived'
ready=false
for _ in $(seq 1 30); do
  if ssh "${ssh_opts[@]}" "root@${gateways[0]}" \
    "COMMON_SPACE_ID='${COMMON_SPACE_ID}' bash -s" <<'REMOTE'
     ip -4 -o addr show dev eth0 | grep -q "10.200.0.209/24" &&
     systemctl is-active --quiet nfs-ganesha &&
     ss -H -lnt sport = :2049 | grep -q . &&
     busctl call org.ganesha.nfsd /org/ganesha/nfsd/ExportMgr \
       org.ganesha.nfsd.exportmgr ShowExports |
       tee /tmp/nfs-exports.ready |
       grep -q "100 \"/users/sulibot/Cloud\"" &&
     grep -q "101 \"/users/projects/${COMMON_SPACE_ID}\"" \
       /tmp/nfs-exports.ready
REMOTE
  then
    ready=true
    break
  fi
  sleep 1
done
if [[ "${ready}" != true ]]; then
  ssh "${ssh_opts[@]}" "root@${gateways[0]}" \
    'journalctl -u nfs-ganesha -u keepalived -n 100 --no-pager'
  exit 1
fi

ssh "${ssh_opts[@]}" "root@${gateways[1]}" 'systemctl start keepalived'
ssh "${ssh_opts[@]}" "root@${gateways[0]}" \
  'systemctl is-active --quiet nfs-ganesha keepalived'
ssh "${ssh_opts[@]}" "root@${gateways[1]}" \
  'systemctl is-active --quiet keepalived; ! systemctl is-active --quiet nfs-ganesha'
