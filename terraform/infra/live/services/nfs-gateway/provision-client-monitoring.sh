#!/bin/bash
# Install an end-to-end NFS probe on the always-on Debian validation VM.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends nfs-common prometheus-node-exporter

install -d -m 0755 /var/lib/prometheus/node-exporter
install -d -m 0755 /var/lib/nfs-gateway-monitor
install -d -m 0755 /mnt/nfs-gateway-probe

cat >/etc/default/prometheus-node-exporter <<'EOF'
ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter"
EOF

cat >/usr/local/sbin/nfs-client-probe <<'EOF'
#!/bin/bash
set -u

endpoint=10.200.0.209
export_path=/shared
mount_dir=/mnt/nfs-gateway-probe
metrics_dir=/var/lib/prometheus/node-exporter
state_dir=/var/lib/nfs-gateway-monitor
output="${metrics_dir}/nfs_client_probe.prom"
temporary="${output}.$$"
client="$(hostname -s)"
probe_file="${mount_dir}/.sre-probe-${client}"
payload="nfs-gateway-probe:${client}"
started_ns="$(date +%s%N)"
success=0
mounted=0

cleanup() {
  if [[ "${mounted}" == 1 ]] || mountpoint -q "${mount_dir}"; then
    umount "${mount_dir}" >/dev/null 2>&1 ||
      umount -l "${mount_dir}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if mountpoint -q "${mount_dir}"; then
  umount -l "${mount_dir}" >/dev/null 2>&1 || true
fi

# This is a monitoring-only mount. Soft failure is intentional so a dead NFS
# endpoint cannot pin the probe process in uninterruptible IO.
if timeout 12 mount -t nfs4 \
  -o vers=4.1,proto=tcp,soft,timeo=20,retrans=1,nosuid,nodev,noexec \
  "${endpoint}:${export_path}" "${mount_dir}"; then
  mounted=1
  if timeout 8 setpriv --reuid=1000 --regid=1000 --clear-groups \
    bash -c "umask 077
      printf '%s\n' '${payload}' > '${probe_file}'
      grep -qxF '${payload}' '${probe_file}'
      rm -f '${probe_file}'"; then
    success=1
    date +%s >"${state_dir}/last_success"
  fi
fi

ended_ns="$(date +%s%N)"
duration="$(awk -v ns="$((ended_ns - started_ns))" 'BEGIN { printf "%.6f", ns / 1000000000 }')"
last_success=0
if [[ -r "${state_dir}/last_success" ]]; then
  read -r last_success <"${state_dir}/last_success" || last_success=0
fi

cat >"${temporary}" <<METRICS
# HELP homeops_nfs_client_probe_success Whether the NFS mount and UID 1000 write-read-delete transaction succeeded.
# TYPE homeops_nfs_client_probe_success gauge
homeops_nfs_client_probe_success{client="${client}",endpoint="${endpoint}",export="${export_path}"} ${success}
# HELP homeops_nfs_client_probe_duration_seconds End-to-end NFS probe duration.
# TYPE homeops_nfs_client_probe_duration_seconds gauge
homeops_nfs_client_probe_duration_seconds{client="${client}",endpoint="${endpoint}",export="${export_path}"} ${duration}
# HELP homeops_nfs_client_probe_timestamp_seconds Unix timestamp of the latest probe attempt.
# TYPE homeops_nfs_client_probe_timestamp_seconds gauge
homeops_nfs_client_probe_timestamp_seconds{client="${client}",endpoint="${endpoint}",export="${export_path}"} $(date +%s)
# HELP homeops_nfs_client_probe_last_success_timestamp_seconds Unix timestamp of the latest successful probe.
# TYPE homeops_nfs_client_probe_last_success_timestamp_seconds gauge
homeops_nfs_client_probe_last_success_timestamp_seconds{client="${client}",endpoint="${endpoint}",export="${export_path}"} ${last_success}
METRICS

chmod 0644 "${temporary}"
mv -f "${temporary}" "${output}"
exit 0
EOF
chmod 0755 /usr/local/sbin/nfs-client-probe

cat >/etc/systemd/system/nfs-client-probe.service <<'EOF'
[Unit]
Description=End-to-end NFS gateway write/read/delete probe
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nfs-client-probe
TimeoutStartSec=25s
EOF

cat >/etc/systemd/system/nfs-client-probe.timer <<'EOF'
[Unit]
Description=Probe the shared NFS endpoint every 30 seconds

[Timer]
OnBootSec=15s
OnUnitActiveSec=30s
AccuracySec=1s
RandomizedDelaySec=2s
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now prometheus-node-exporter nfs-client-probe.timer >/dev/null
systemctl start nfs-client-probe.service
