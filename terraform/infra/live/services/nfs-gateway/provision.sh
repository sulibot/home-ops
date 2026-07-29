#!/usr/bin/env bash
set -euo pipefail

: "${NFS_VIP4:?NFS_VIP4 is required}"
: "${NFS_VIP6:?NFS_VIP6 is required}"
: "${NFS_NODES4:?NFS_NODES4 is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  ceph-common \
  keepalived \
  nfs-common \
  nfs-ganesha \
  nfs-ganesha-ceph \
  nfs-ganesha-rados-grace

hostname_short="$(hostname -s)"
node_ipv4="$(ip -4 -o addr show dev eth0 scope global | awk '{print $4}' | cut -d/ -f1 | head -n1)"

peer_ipv4=""
for candidate in ${NFS_NODES4}; do
  if [[ "${candidate}" != "${node_ipv4}" ]]; then
    peer_ipv4="${candidate}"
  fi
done
if [[ -z "${peer_ipv4}" ]]; then
  echo "Could not derive Keepalived peer from NFS_NODES4=${NFS_NODES4}" >&2
  exit 1
fi

case "${hostname_short}" in
  nfsgw01)
    priority=150
    node_ipv6="fd00:200::207"
    peer_ipv6="fd00:200::208"
    ceph_route_gateway="fd00:200::1"
    ;;
  nfsgw02)
    priority=100
    node_ipv6="fd00:200::208"
    peer_ipv6="fd00:200::207"
    ceph_route_gateway="fd00:200::2"
    ;;
  *)
    echo "Unsupported NFS gateway hostname: ${hostname_short}" >&2
    exit 1
    ;;
esac

install -d -m 0750 /etc/ganesha /etc/ceph

cat >/etc/systemd/system/nfs-gateway-ceph-route.service <<EOF
[Unit]
Description=Route Ceph public messenger traffic through the local PVE node
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip -6 route replace fc00:20::/64 via ${ceph_route_gateway} dev eth0
ExecStop=/usr/sbin/ip -6 route del fc00:20::/64 via ${ceph_route_gateway} dev eth0

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/ganesha/ganesha.conf <<EOF
NFS_CORE_PARAM {
    Protocols = 4;
    Enable_NLM = false;
    Enable_RQUOTA = false;
}

NFSv4 {
    Minor_Versions = 1, 2;
    RecoveryBackend = rados_ng;
    Allow_Numeric_Owners = true;
    Only_Numeric_Owners = true;
}

MDCACHE {
    Dir_Chunk = 0;
}

EXPORT_DEFAULTS {
    Access_Type = NONE;
    Protocols = 4;
    Transports = TCP;
    SecType = sys;
    Squash = Root_Squash;
}

EXPORT {
    Export_Id = 100;
    Path = /users/sulibot/Cloud;
    Pseudo = /shared;
    Access_Type = RW;
    Attr_Expiration_Time = 0;

    FSAL {
        Name = CEPH;
        Filesystem = content;
        User_Id = nfs-shared;
        cmount_path = /users/sulibot/Cloud;
    }

    CLIENT {
        Clients = 10.200.0.0/24, fd00:200::/64;
        Access_Type = RW;
        Squash = Root_Squash;
    }
}

CEPH {
    Ceph_Conf = /etc/ceph/ceph.conf;
}

RADOS_KV {
    Ceph_Conf = /etc/ceph/ceph.conf;
    UserId = nfs-recovery;
    pool = nfs-ganesha;
    nodeid = nfs-shared;
}
EOF

cat >/usr/local/sbin/check-nfs-ganesha <<EOF
#!/bin/sh
# A standby is healthy without Ganesha. Once this node owns the VIP, failure
# of the logical NFS server lowers its VRRP priority and promotes the peer.
if [ -e /run/nfs-gateway-inhibit ]; then
    exit 1
fi
if [ -e /run/nfs-gateway-starting ]; then
    exit 0
fi
if ! ip -4 -o addr show dev eth0 | grep -q '${NFS_VIP4}/24'; then
    rm -f /run/nfs-gateway-health-failures
    exit 0
fi
if systemctl is-active --quiet nfs-ganesha &&
   ss -H -lnt sport = :2049 | grep -q . &&
   busctl call org.ganesha.nfsd /org/ganesha/nfsd/ExportMgr \
     org.ganesha.nfsd.exportmgr ShowExports |
     grep -q '100 "/users/sulibot/Cloud"'; then
    rm -f /run/nfs-gateway-health-failures
    exit 0
fi
failures=0
if [ -r /run/nfs-gateway-health-failures ]; then
    read -r failures </run/nfs-gateway-health-failures || failures=0
fi
failures=\$((failures + 1))
printf '%s\n' "\${failures}" >/run/nfs-gateway-health-failures
if [ "\${failures}" -ge 2 ]; then
    touch /run/nfs-gateway-inhibit
fi
exit 1
EOF
chmod 0755 /usr/local/sbin/check-nfs-ganesha

cat >/usr/local/sbin/nfs-gateway-state <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  master)
    rm -f /run/nfs-gateway-inhibit /run/nfs-gateway-health-failures
    touch /run/nfs-gateway-starting
    systemctl kill --kill-whom=main --signal=KILL nfs-ganesha 2>/dev/null || true
    systemctl reset-failed nfs-ganesha 2>/dev/null || true
    systemctl start nfs-ganesha
    ready=false
    for _ in $(seq 1 30); do
      if systemctl is-active --quiet nfs-ganesha &&
         ss -H -lnt sport = :2049 | grep -q . &&
         busctl call org.ganesha.nfsd /org/ganesha/nfsd/ExportMgr \
           org.ganesha.nfsd.exportmgr ShowExports |
           grep -q '100 "/users/sulibot/Cloud"'; then
        ready=true
        break
      fi
      sleep 1
    done
    rm -f /run/nfs-gateway-starting
    if [ "${ready}" != true ]; then
      touch /run/nfs-gateway-inhibit
      exit 1
    fi
    ;;
  backup|fault|stop)
    rm -f /run/nfs-gateway-starting
    systemctl kill --kill-whom=main --signal=KILL nfs-ganesha 2>/dev/null || true
    systemctl reset-failed nfs-ganesha 2>/dev/null || true
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 /usr/local/sbin/nfs-gateway-state

install -d -m 0755 /etc/systemd/system/nfs-ganesha.service.d
cat >/etc/systemd/system/nfs-ganesha.service.d/restart.conf <<'EOF'
[Service]
Restart=no
EOF

cat >/etc/keepalived/keepalived.conf <<EOF
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_ganesha {
    script "/usr/local/sbin/check-nfs-ganesha"
    interval 2
    timeout 2
    fall 2
    rise 3
    weight -80
}

vrrp_instance NFS4 {
    state BACKUP
    interface eth0
    virtual_router_id 209
    priority ${priority}
    advert_int 1
    unicast_src_ip ${node_ipv4}
    unicast_peer {
        ${peer_ipv4}
    }
    authentication {
        auth_type PASS
        auth_pass nfsvip20
    }
    virtual_ipaddress {
        ${NFS_VIP4}/24 dev eth0
    }
    track_script {
        chk_ganesha
    }
    notify_master "/usr/local/sbin/nfs-gateway-state master"
    notify_backup "/usr/local/sbin/nfs-gateway-state backup"
    notify_fault "/usr/local/sbin/nfs-gateway-state fault"
    notify_stop "/usr/local/sbin/nfs-gateway-state stop"
}

vrrp_instance NFS6 {
    state BACKUP
    interface eth0
    virtual_router_id 210
    priority ${priority}
    advert_int 1
    native_ipv6
    unicast_src_ip ${node_ipv6}
    unicast_peer {
        ${peer_ipv6}
    }
    virtual_ipaddress {
        ${NFS_VIP6}/64 dev eth0
    }
    track_script {
        chk_ganesha
    }
    notify_master "/usr/local/sbin/nfs-gateway-state master"
    notify_backup "/usr/local/sbin/nfs-gateway-state backup"
    notify_fault "/usr/local/sbin/nfs-gateway-state fault"
    notify_stop "/usr/local/sbin/nfs-gateway-state stop"
}
EOF

# Ceph credentials are installed in a separate no-state step. Ganesha must not
# race ahead with absent keyrings, while Keepalived must never advertise a VIP
# for an unhealthy NFS daemon.
systemctl disable --now keepalived nfs-ganesha >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable --now nfs-gateway-ceph-route.service >/dev/null
systemctl enable nfs-ganesha keepalived >/dev/null
