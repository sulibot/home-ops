#!/usr/bin/env bash
# Configure one Debian LXC as an OpenBao Raft member with a leader-gated
# BGP service VIP. Terraform supplies only non-secret topology parameters.
set -euo pipefail

required_env=(
  OPENBAO_VERSION
  OPENBAO_SHA256
  OPENBAO_TENANT
  OPENBAO_DOMAIN
  OPENBAO_BASE_DOMAIN
  OPENBAO_VIP4
  OPENBAO_VIP6
  OPENBAO_PEERS4
  OPENBAO_BGP_PEER4
  OPENBAO_BGP_PEER6
  OPENBAO_BGP_PEER_AS
  OPENBAO_SEAL_TYPE
  OPENBAO_GCP_KMS_PROJECT_ID
  OPENBAO_GCP_KMS_LOCATION
  OPENBAO_GCP_KMS_KEY_RING
  OPENBAO_GCP_KMS_CRYPTO_KEY
)

for name in "${required_env[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "missing required environment variable: $name" >&2
    exit 1
  fi
done

if [[ "$OPENBAO_SEAL_TYPE" != "gcpckms" ]]; then
  echo "unsupported OpenBao seal type: $OPENBAO_SEAL_TYPE" >&2
  exit 1
fi
for value in \
  "$OPENBAO_GCP_KMS_PROJECT_ID" \
  "$OPENBAO_GCP_KMS_LOCATION" \
  "$OPENBAO_GCP_KMS_KEY_RING" \
  "$OPENBAO_GCP_KMS_CRYPTO_KEY"; do
  if [[ ! "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "invalid GCP KMS resource selector: $value" >&2
    exit 1
  fi
done

export DEBIAN_FRONTEND=noninteractive

ip4="$(ip -4 -o addr show dev eth0 scope global | awk '{print $4}' | cut -d/ -f1 | head -n1)"
node_name="$(hostname -s)"

if [[ -z "$ip4" ]]; then
  echo "unable to determine eth0 IPv4 address" >&2
  exit 1
fi

node_suffix="${ip4##*.}"
if [[ ! "$OPENBAO_TENANT" =~ ^[0-9]+$ || ! "$node_suffix" =~ ^[0-9]+$ ]]; then
  echo "tenant and IPv4 node suffix must be numeric" >&2
  exit 1
fi

# Debian also creates a stable EUI-64 address from the PVE-provided MAC.
# Select the explicitly assigned ::<IPv4-suffix> address so FRR's narrow
# /128 dynamic-neighbor allowlist and BIRD always agree.
ip6="$(
  ip -6 -o addr show dev eth0 scope global |
    awk '{print $4}' |
    cut -d/ -f1 |
    grep -E "::${node_suffix}$" |
    head -n1
)"
if [[ -z "$ip6" ]]; then
  echo "unable to determine static eth0 IPv6 address ending in ::$node_suffix" >&2
  exit 1
fi

local_as="$((4210000000 + OPENBAO_TENANT * 1000 + node_suffix))"
node_fqdn="$node_name.$OPENBAO_BASE_DOMAIN"

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  bird2 \
  ca-certificates \
  curl \
  jq \
  logrotate \
  rclone \
  rsyslog \
  openssl

installed_version="$(dpkg-query -W -f='${Version}' openbao 2>/dev/null || true)"
if [[ "$installed_version" != "$OPENBAO_VERSION" ]]; then
  if [[ -n "$installed_version" ]] &&
    find /opt/openbao/data/raft -mindepth 1 -maxdepth 1 -type f -size +0c \
      -print -quit 2>/dev/null | grep -q .; then
    echo "refusing an in-place OpenBao upgrade from $installed_version to $OPENBAO_VERSION" >&2
    echo "upgrade initialized Raft members one standby at a time using the runbook" >&2
    exit 1
  fi

  package="/tmp/openbao_${OPENBAO_VERSION}_linux_amd64.deb"
  curl -fsSL \
    -o "$package" \
    "https://github.com/openbao/openbao/releases/download/v${OPENBAO_VERSION}/openbao_${OPENBAO_VERSION}_linux_amd64.deb"
  printf '%s  %s\n' "$OPENBAO_SHA256" "$package" | sha256sum --check -
  apt-get install -y -qq "$package"
  rm -f "$package"
fi

install -d -m 0750 -o openbao -g openbao \
  /etc/openbao/tls \
  /opt/openbao/data/raft \
  /var/log/openbao

# The Debian package creates a self-signed bootstrap pair. Preserve a real
# certificate already installed by the separate TLS sync step.
if [[ ! -s /etc/openbao/tls/tls.crt || ! -s /etc/openbao/tls/tls.key ]]; then
  install -m 0644 -o root -g openbao /opt/openbao/tls/tls.crt /etc/openbao/tls/tls.crt
  install -m 0640 -o root -g openbao /opt/openbao/tls/tls.key /etc/openbao/tls/tls.key
fi

# The IPv6 wildcard is dual-stack on Linux and serves both routed VIPs
# without competing IPv4 and IPv6 listener sockets.
new_config="$(mktemp)"
cat >"$new_config" <<EOF
ui           = true
cluster_name = "sulibot-openbao"
log_level    = "info"

# Keep redirection and cluster forwarding node-specific. Normal clients use
# the leader-gated service VIP and should never need a redirect.
api_addr     = "https://$node_fqdn"
cluster_addr = "https://$ip4:8201"

seal "gcpckms" {
  credentials = "/etc/openbao/gcp-kms-credentials.json"
  project     = "$OPENBAO_GCP_KMS_PROJECT_ID"
  region      = "$OPENBAO_GCP_KMS_LOCATION"
  key_ring    = "$OPENBAO_GCP_KMS_KEY_RING"
  crypto_key  = "$OPENBAO_GCP_KMS_CRYPTO_KEY"
}

listener "tcp" {
  address         = "[::]:443"
  cluster_address = "[::]:8201"
  tls_cert_file   = "/etc/openbao/tls/tls.crt"
  tls_key_file    = "/etc/openbao/tls/tls.key"
  tls_min_version = "tls12"

  telemetry {
    disallow_metrics = true
  }
}

# Keep unauthenticated metrics off the public client listener. This listener is
# reachable only on the node addresses and is scraped by the in-cluster
# ServiceMonitor through a fixed Endpoints object.
listener "tcp" {
  address         = "[::]:9101"
  tls_cert_file   = "/etc/openbao/tls/tls.crt"
  tls_key_file    = "/etc/openbao/tls/tls.key"
  tls_min_version = "tls12"

  telemetry {
    metrics_only                   = true
    unauthenticated_metrics_access = true
  }
}

storage "raft" {
  path                   = "/opt/openbao/data/raft"
  node_id                = "$node_name"
  performance_multiplier = 5
EOF

for peer in $OPENBAO_PEERS4; do
  if [[ "$peer" == "$ip4" ]]; then
    continue
  fi
  cat >>"$new_config" <<EOF

  retry_join {
    leader_api_addr       = "https://$peer"
    leader_tls_servername = "$OPENBAO_DOMAIN"
  }
EOF
done

cat >>"$new_config" <<'EOF'
}

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = true
}

# OpenBao 2.6 defaults to safe, configuration-owned audit devices. Keep a
# durable local file plus local syslog; rsyslog forwards only this program to
# the Kubernetes security-log pipeline.
audit "file" "file" {
  description = "Durable local audit fallback"

  options {
    file_path = "/var/log/openbao/audit.json"
    mode      = "0640"
    log_raw   = "false"
  }
}

audit "syslog" "syslog" {
  description = "Forward audit events through the local syslog agent"

  options {
    tag      = "openbao-audit"
    facility = "AUTH"
    log_raw  = "false"
  }
}
EOF

config_changed=0
if ! cmp -s "$new_config" /etc/openbao/openbao.hcl; then
  if systemctl is-active --quiet openbao.service; then
    initialized="$(curl --silent --insecure --connect-timeout 2 --max-time 3 \
      --resolve "$OPENBAO_DOMAIN:443:127.0.0.1" \
      "https://$OPENBAO_DOMAIN/v1/sys/health" |
      jq -r '.initialized // false' 2>/dev/null || printf 'false')"
    if [[ "$initialized" == "true" ]] &&
      [[ "${OPENBAO_ALLOW_INITIALIZED_CONFIG_CHANGE:-false}" != "true" ]]; then
      rm -f "$new_config"
      echo "OpenBao config changed on initialized member $node_name." >&2
      echo "Use the rolling maintenance procedure; Terraform left the live config unchanged." >&2
      exit 1
    fi
  fi
  config_changed=1
  install -m 0640 -o root -g openbao "$new_config" /etc/openbao/openbao.hcl
fi
rm -f "$new_config"

# The file audit device is the durable local fallback. OpenBao reopens the file
# on SIGHUP after rotation, avoiding copytruncate and lost audit records.
cat >/etc/logrotate.d/openbao-audit <<'EOF'
/var/log/openbao/audit.json {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  create 0640 openbao openbao
  sharedscripts
  postrotate
    /bin/systemctl kill --kill-who=main --signal=HUP openbao.service >/dev/null 2>&1 || true
  endscript
}
EOF

# Forward only the dedicated OpenBao audit program to the infrastructure log
# collector. The local file above remains authoritative if the collector is
# unavailable; rsyslog uses a disk-assisted queue for extended outages.
cat >/etc/rsyslog.d/30-openbao-audit.conf <<EOF
if \$programname == 'openbao-audit' then {
  action(
    type="omfwd"
    target="${OPENBAO_AUDIT_SYSLOG_HOST:-10.101.250.125}"
    port="${OPENBAO_AUDIT_SYSLOG_PORT:-2515}"
    protocol="tcp"
    TCP_Framing="octet-counted"
    template="RSYSLOG_SyslogProtocol23Format"
    action.resumeRetryCount="-1"
    queue.type="LinkedList"
    queue.filename="openbao-audit"
    queue.spoolDirectory="/var/spool/rsyslog"
    queue.saveOnShutdown="on"
  )
  stop
}
EOF
rsyslogd -N1
systemctl enable --now rsyslog.service
systemctl restart rsyslog.service

install -d -m 0755 /etc/systemd/system/openbao.service.d
cat >/etc/systemd/system/openbao.service.d/override.conf <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
# OpenBao binds directly to the standard HTTPS port. Retain the upstream
# package hardening while granting only the low-port capability.
CapabilityBoundingSet=CAP_SYSLOG CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
# The KMS principal is restricted to encrypt, decrypt, and key metadata access
# on one key. Terraform streams this file from 1Password after provisioning.
Environment=GOOGLE_APPLICATION_CREDENTIALS=/etc/openbao/gcp-kms-credentials.json
Restart=on-failure
RestartSec=5s
EOF

cat >/etc/bird/bird.conf <<EOF
log syslog all;
router id $ip4;

define VIP4 = $OPENBAO_VIP4/32;
define VIP6 = $OPENBAO_VIP6/128;
define LOCAL_AS = $local_as;
define PEER_AS = $OPENBAO_BGP_PEER_AS;
define PEER6 = $OPENBAO_BGP_PEER6;

protocol device {}

# Do not import lo. The disabled/enabled static protocols below must be the
# sole BIRD source for the VIPs or a failed health check cannot withdraw them.
protocol direct connected {
  ipv4;
  ipv6;
  interface "eth0";
}

protocol bfd {
  interface "eth0" {
    interval 300 ms;
    multiplier 3;
  };
}

protocol static service_vip4 {
  disabled;
  ipv4;
  route VIP4 blackhole;
}

protocol static service_vip6 {
  disabled;
  ipv6;
  route VIP6 blackhole;
}

protocol bgp upstream {
  local as LOCAL_AS;
  neighbor PEER6 as PEER_AS;
  source address $ip6;
  bfd on;
  connect retry time 3;
  hold time 9;
  keepalive time 3;
  ipv4 {
    import none;
    export where net = VIP4;
    next hop self;
    extended next hop on;
  };
  ipv6 {
    import none;
    export where net = VIP6;
  };
}
EOF

cat >/usr/local/sbin/openbao-service-vip <<EOF
#!/usr/bin/env bash
set -euo pipefail
ip -4 address show dev lo | grep -qF '$OPENBAO_VIP4/32' ||
  ip -4 address add '$OPENBAO_VIP4/32' dev lo
ip -6 address show dev lo | grep -qF '$OPENBAO_VIP6/128' ||
  ip -6 address add '$OPENBAO_VIP6/128' dev lo
EOF
chmod 0750 /usr/local/sbin/openbao-service-vip

cat >/etc/systemd/system/openbao-service-vip.service <<'EOF'
[Unit]
Description=Assign OpenBao routed service VIPs to loopback
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/openbao-service-vip
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat >/usr/local/sbin/openbao-leader-route-health <<EOF
#!/usr/bin/env bash
set -euo pipefail

# A 204 is returned only by the initialized, unsealed active node. Standbys,
# sealed nodes, and uninitialized nodes must not originate the service route.
if curl --silent --show-error --fail --output /dev/null --max-time 2 --insecure \
  --resolve '$OPENBAO_DOMAIN:443:127.0.0.1' \
  'https://$OPENBAO_DOMAIN/v1/sys/health?activecode=204&standbycode=429&sealedcode=503&uninitcode=501'; then
  birdc enable service_vip4 >/dev/null 2>&1 || true
  birdc enable service_vip6 >/dev/null 2>&1 || true
else
  birdc disable service_vip4 >/dev/null 2>&1 || true
  birdc disable service_vip6 >/dev/null 2>&1 || true
fi
EOF
chmod 0750 /usr/local/sbin/openbao-leader-route-health

cat >/etc/systemd/system/openbao-leader-route-health.service <<'EOF'
[Unit]
Description=Advertise OpenBao service VIP only from the active Raft leader
After=network-online.target bird.service openbao.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/openbao-leader-route-health
EOF

cat >/etc/systemd/system/openbao-leader-route-health.timer <<'EOF'
[Unit]
Description=Check OpenBao leadership and reconcile its BGP service route

[Timer]
OnBootSec=5s
OnUnitActiveSec=2s
AccuracySec=1s
Unit=openbao-leader-route-health.service

[Install]
WantedBy=timers.target
EOF

cat >/etc/profile.d/openbao.sh <<EOF
export VAULT_ADDR='https://$OPENBAO_DOMAIN'
EOF
chmod 0644 /etc/profile.d/openbao.sh

systemctl daemon-reload
systemctl enable --now openbao-service-vip.service
systemctl enable --now bird.service

# Validate and apply BIRD changes without tearing down the daemon. Never
# advertise a service route merely because BIRD started successfully.
birdc configure check
birdc configure
birdc disable service_vip4 >/dev/null 2>&1 || true
birdc disable service_vip6 >/dev/null 2>&1 || true

# The service is enabled now, but it cannot start until Terraform streams the
# restricted GCP KMS principal from 1Password. Keeping the credentials out of
# the provisioning command prevents them from entering Terraform state.
systemctl enable openbao.service
if [[ -s /etc/openbao/gcp-kms-credentials.json ]]; then
  if ! systemctl is-active --quiet openbao.service; then
    systemctl start openbao.service
  elif [[ "$config_changed" -eq 1 ]]; then
    # Initialized members reach this branch only through the explicit rolling
    # reconciler. Normal Terraform provisioning still refuses the change.
    systemctl restart openbao.service
  fi
else
  systemctl stop openbao.service
fi

systemctl enable --now openbao-leader-route-health.timer
/usr/local/sbin/openbao-leader-route-health

systemctl is-active --quiet bird.service
birdc configure check
