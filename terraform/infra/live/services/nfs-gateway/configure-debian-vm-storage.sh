#!/usr/bin/env bash
# Reconcile the storage contract on an already-created Debian validation VM.
# The CephX key remains an out-of-band secret and must already be enrolled.
set -euo pipefail

client="${CLIENT:-10.200.0.205}"
route_gateway="${CEPH_ROUTE_GATEWAY:-fd00:200::3}"
user_uid="${USER_UID:-1888405477}"
user_gid="${USER_GID:-1888405477}"
ssh_key="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
ssh_opts=(-i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

ssh "${ssh_opts[@]}" "root@${client}" \
  "ROUTE_GATEWAY='${route_gateway}' USER_UID='${user_uid}' USER_GID='${user_gid}' bash -s" <<'REMOTE'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends acl attr ceph-common nfs-common

test -s /etc/ceph/ceph.client.sulibot-cloud.keyring
install -d -o "${USER_UID}" -g "${USER_GID}" -m 0700 /home/sulibot
install -d -o "${USER_UID}" -g "${USER_GID}" -m 0750 /home/sulibot/Cloud
install -d -m 0755 /srv/common

grep -qF 'sulibot-cloud@.content=/users/sulibot/Cloud /home/sulibot/Cloud ceph' /etc/fstab ||
  printf '%s\n' \
    'sulibot-cloud@.content=/users/sulibot/Cloud /home/sulibot/Cloud ceph noauto,x-systemd.automount,x-systemd.idle-timeout=10min,_netdev 0 0' \
    >>/etc/fstab
grep -qF '10.200.0.209:/common /srv/common nfs4' /etc/fstab ||
  printf '%s\n' \
    '10.200.0.209:/common /srv/common nfs4 noauto,x-systemd.automount,x-systemd.idle-timeout=10min,_netdev,vers=4.1,proto=tcp,hard 0 0' \
    >>/etc/fstab

cat >/etc/systemd/system/user-storage-ceph-route.service <<EOF
[Unit]
Description=Route Ceph messenger traffic through the local PVE node
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip -6 route replace fc00:20::/64 via ${ROUTE_GATEWAY} dev eth0
ExecStop=/usr/sbin/ip -6 route del fc00:20::/64 via ${ROUTE_GATEWAY} dev eth0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now user-storage-ceph-route.service
systemctl restart remote-fs.target
REMOTE
