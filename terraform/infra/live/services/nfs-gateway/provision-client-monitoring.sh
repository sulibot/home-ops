#!/bin/bash
# Install an end-to-end NFS probe on the always-on Debian validation VM.
set -euo pipefail

: "${COMMON_GID:?COMMON_GID is required}"
: "${USER_UID:?USER_UID is required}"
: "${USER_GID:?USER_GID is required}"

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
mount_dir=/mnt/nfs-gateway-probe
metrics_dir=/var/lib/prometheus/node-exporter
state_dir=/var/lib/nfs-gateway-monitor
output="${metrics_dir}/nfs_client_probe.prom"
temporary="${output}.$$"
client="$(hostname -s)"
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

cat >"${temporary}" <<'METRICS'
# HELP homeops_nfs_client_probe_success Whether the NFS mount and canonical-user write-read-delete transaction succeeded.
# TYPE homeops_nfs_client_probe_success gauge
# HELP homeops_nfs_client_probe_duration_seconds End-to-end NFS probe duration.
# TYPE homeops_nfs_client_probe_duration_seconds gauge
# HELP homeops_nfs_client_probe_timestamp_seconds Unix timestamp of the latest probe attempt.
# TYPE homeops_nfs_client_probe_timestamp_seconds gauge
# HELP homeops_nfs_client_probe_last_success_timestamp_seconds Unix timestamp of the latest successful probe.
# TYPE homeops_nfs_client_probe_last_success_timestamp_seconds gauge
METRICS

for probe in personal:/shared:@@USER_GID@@ common:/common:@@COMMON_GID@@; do
  name="${probe%%:*}"
  remainder="${probe#*:}"
  export_path="${remainder%%:*}"
  gid="${remainder##*:}"
  probe_file="${mount_dir}/.sre-probe-${client}-${name}"
  payload="nfs-gateway-probe:${client}:${name}"
  last_success_file="${state_dir}/last_success_${name}"
  started_ns="$(date +%s%N)"
  success=0

  if mountpoint -q "${mount_dir}"; then
    umount -l "${mount_dir}" >/dev/null 2>&1 || true
  fi

  # This is a monitoring-only mount. Soft failure is intentional so a dead NFS
  # endpoint cannot pin the probe process in uninterruptible IO.
  if timeout 8 mount -t nfs4 \
    -o vers=4.1,proto=tcp,soft,timeo=15,retrans=1,nosuid,nodev,noexec \
    "${endpoint}:${export_path}" "${mount_dir}"; then
    mounted=1
    if timeout 5 setpriv --reuid=@@USER_UID@@ --regid="${gid}" --clear-groups \
      bash -c "umask 077
        printf '%s\n' '${payload}' > '${probe_file}'
        grep -qxF '${payload}' '${probe_file}'
        rm -f '${probe_file}'"; then
      success=1
      date +%s >"${last_success_file}"
    fi
    umount "${mount_dir}" >/dev/null 2>&1 ||
      umount -l "${mount_dir}" >/dev/null 2>&1 || true
    mounted=0
  fi

  ended_ns="$(date +%s%N)"
  duration="$(awk -v ns="$((ended_ns - started_ns))" 'BEGIN { printf "%.6f", ns / 1000000000 }')"
  last_success=0
  if [[ -r "${last_success_file}" ]]; then
    read -r last_success <"${last_success_file}" || last_success=0
  fi

  cat >>"${temporary}" <<METRICS
homeops_nfs_client_probe_success{client="${client}",endpoint="${endpoint}",export="${export_path}"} ${success}
homeops_nfs_client_probe_duration_seconds{client="${client}",endpoint="${endpoint}",export="${export_path}"} ${duration}
homeops_nfs_client_probe_timestamp_seconds{client="${client}",endpoint="${endpoint}",export="${export_path}"} $(date +%s)
homeops_nfs_client_probe_last_success_timestamp_seconds{client="${client}",endpoint="${endpoint}",export="${export_path}"} ${last_success}
METRICS
done

chmod 0644 "${temporary}"
mv -f "${temporary}" "${output}"
exit 0
EOF
sed -i "s/@@COMMON_GID@@/${COMMON_GID}/g" \
  /usr/local/sbin/nfs-client-probe
sed -i "s/@@USER_UID@@/${USER_UID}/g; s/@@USER_GID@@/${USER_GID}/g" \
  /usr/local/sbin/nfs-client-probe
chmod 0755 /usr/local/sbin/nfs-client-probe

cat >/etc/systemd/system/nfs-client-probe.service <<'EOF'
[Unit]
Description=End-to-end NFS gateway write/read/delete probe
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nfs-client-probe
TimeoutStartSec=35s
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
