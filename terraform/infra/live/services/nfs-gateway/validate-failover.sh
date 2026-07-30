#!/usr/bin/env bash
# Disruptive validation: stop the primary Ganesha service and prove that an
# existing hard-mounted NFS client completes I/O through the peer.
set -euo pipefail

client="${PVE_CLIENT:-10.200.0.205}"
primary="${NFS_PRIMARY:-10.200.0.207}"
secondary="${NFS_SECONDARY:-10.200.0.208}"
vip4="${NFS_VIP4:-10.200.0.209}"
user_uid="${USER_UID:-1888405477}"
user_gid="${USER_GID:-1888405477}"
mount_dir="$(ssh "root@${client}" 'mktemp -d /mnt/nfs-failover.XXXXXX')"

cleanup() {
  rc=$?
  trap - EXIT
  set +e
  ssh "root@${primary}" \
    'rm -f /run/nfs-gateway-inhibit; systemctl start keepalived' >/dev/null
  ssh "root@${secondary}" 'systemctl stop keepalived' >/dev/null
  sleep 5
  ssh "root@${secondary}" 'systemctl start keepalived' >/dev/null
  ssh "root@${client}" \
    "setpriv --reuid='${user_uid}' --regid='${user_gid}' --clear-groups rm -f \
      '${mount_dir}/.before-failover' '${mount_dir}/.after-failover';
     if mountpoint -q '${mount_dir}'; then
       umount -f '${mount_dir}' 2>/dev/null || umount -l '${mount_dir}';
     fi;
     rmdir '${mount_dir}'" >/dev/null
  exit "${rc}"
}
trap cleanup EXIT

ssh "root@${client}" \
  "mount -t nfs4 -o vers=4.1,proto=tcp,hard,timeo=50,retrans=2 \
     '${vip4}:/shared' '${mount_dir}';
   setpriv --reuid='${user_uid}' --regid='${user_gid}' --clear-groups sh -c \
     \"printf 'before-failover\\n' > '${mount_dir}/.before-failover'\""

ssh "root@${primary}" \
  'systemctl kill --kill-whom=main --signal=KILL nfs-ganesha'

peer_ready=false
for _ in $(seq 1 30); do
  primary4="$(ssh "root@${primary}" \
    "ip -4 -o addr show dev eth0 | grep -c '${vip4}/24' || true")"
  secondary4="$(ssh "root@${secondary}" \
    "ip -4 -o addr show dev eth0 | grep -c '${vip4}/24' || true")"
  if [[ "${primary4}:${secondary4}" == "0:1" ]] &&
     ssh "root@${secondary}" '/usr/local/sbin/check-nfs-ganesha'; then
    peer_ready=true
    break
  fi
  sleep 1
done
[[ "${peer_ready}" == true ]]
printf 'VIP moved to the secondary gateway\n'

ssh "root@${client}" \
  "timeout 150 setpriv --reuid='${user_uid}' --regid='${user_gid}' --clear-groups \
     grep -qx before-failover '${mount_dir}/.before-failover';
   timeout 150 setpriv --reuid='${user_uid}' --regid='${user_gid}' --clear-groups sh -c \
     \"printf 'after-failover\\n' > '${mount_dir}/.after-failover'\""
printf 'Existing client mount completed I/O through the secondary\n'

# Controlled failback: stopping the active peer withdraws the VIP and Ganesha;
# the preferred node promotes and starts the same logical NFS server identity.
ssh "root@${primary}" 'rm -f /run/nfs-gateway-inhibit'
ssh "root@${secondary}" 'systemctl stop keepalived'

primary_ready=false
for _ in $(seq 1 30); do
  if ssh "root@${primary}" \
    "/usr/local/sbin/check-nfs-ganesha &&
     ip -4 -o addr show dev eth0 | grep -q '${vip4}/24'"; then
    primary_ready=true
    break
  fi
  sleep 1
done
[[ "${primary_ready}" == true ]]

ssh "root@${client}" \
  "timeout 150 setpriv --reuid='${user_uid}' --regid='${user_gid}' --clear-groups \
     grep -qx after-failover '${mount_dir}/.after-failover'"
printf 'Primary recovery and post-recovery I/O succeeded\n'

ssh "root@${secondary}" 'systemctl start keepalived'
