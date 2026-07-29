#!/usr/bin/env bash
# Install the scoped OpenBao Raft snapshot timer on every member without
# putting AppRole or B2 credentials into Terraform state or command output.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
onepassword_vault="${OPENBAO_1PASSWORD_VAULT:-Kubernetes}"
: "${OPENBAO_NODES:?OPENBAO_NODES is required}"

read_field() {
  local item="$1"
  local field="$2"
  op item get "$item" \
    --vault "$onepassword_vault" \
    --format=json \
    --reveal |
    jq -er --arg field "$field" '
      .fields[] |
      select(.label == $field or .id == $field) |
      .value
    ' |
    head -n1
}

role_id="$(read_field openbao-approle-backup username)"
secret_id="$(read_field openbao-approle-backup password)"
b2_endpoint="$(read_field offsite-backup-s3 s3-endpoint)"
b2_region="$(read_field offsite-backup-s3 region)"
b2_bucket="$(read_field offsite-backup-s3 infrastructure-bucket)"
b2_access_key="$(read_field offsite-backup-s3 infrastructure-access-key-id)"
b2_application_key="$(read_field offsite-backup-s3 infrastructure-application-key)"

for value in \
  "$role_id" \
  "$secret_id" \
  "$b2_region" \
  "$b2_bucket" \
  "$b2_access_key" \
  "$b2_application_key"; do
  if [[ ! "$value" =~ ^[A-Za-z0-9._/+=-]+$ ]]; then
    echo "refusing unsafe OpenBao backup credential value" >&2
    exit 1
  fi
done
if [[ ! "$b2_endpoint" =~ ^https://[A-Za-z0-9.-]+$ ]]; then
  echo "refusing unsafe B2 endpoint" >&2
  exit 1
fi

ssh_options=(
  -i "$HOME/.ssh/id_ed25519"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

for node in $OPENBAO_NODES; do
  if ! ssh "${ssh_options[@]}" "root@$node" 'command -v rclone >/dev/null'; then
    ssh "${ssh_options[@]}" "root@$node" \
      'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; apt-get install -y -qq --no-install-recommends rclone >/dev/null'
  fi

  printf '%s\n' \
    "OPENBAO_ROLE_ID=$role_id" \
    "OPENBAO_SECRET_ID=$secret_id" \
    "B2_S3_ENDPOINT=$b2_endpoint" \
    "B2_REGION=$b2_region" \
    "B2_INFRA_BUCKET=$b2_bucket" \
    "B2_INFRA_ACCESS_KEY_ID=$b2_access_key" \
    "B2_INFRA_APPLICATION_KEY=$b2_application_key" |
    ssh "${ssh_options[@]}" "root@$node" \
      'install -d -m 0750 /etc/openbao; install -d -m 0700 /var/backups/openbao; install -m 0600 -o root -g root /dev/stdin /etc/openbao/backup.env'

  ssh "${ssh_options[@]}" "root@$node" \
    'install -m 0750 -o root -g root /dev/stdin /usr/local/sbin/openbao-backup' \
    <"$script_dir/openbao-backup.sh"

  printf '%s\n' \
    '[Unit]' \
    'Description=Save and upload an application-consistent OpenBao Raft snapshot' \
    'After=network-online.target openbao.service' \
    'Wants=network-online.target' \
    '' \
    '[Service]' \
    'Type=oneshot' \
    'EnvironmentFile=/etc/openbao/backup.env' \
    'ExecStart=/usr/local/sbin/openbao-backup' \
    'UMask=0077' \
    'NoNewPrivileges=true' \
    'PrivateTmp=true' \
    'ProtectHome=true' \
    'ProtectSystem=strict' \
    'ReadWritePaths=/var/backups/openbao' |
    ssh "${ssh_options[@]}" "root@$node" \
      'install -m 0644 -o root -g root /dev/stdin /etc/systemd/system/openbao-backup.service'

  printf '%s\n' \
    '[Unit]' \
    'Description=Run the OpenBao Raft snapshot every six hours' \
    '' \
    '[Timer]' \
    'OnCalendar=*-*-* 00/6:20:00' \
    'RandomizedDelaySec=10m' \
    'Persistent=true' \
    'Unit=openbao-backup.service' \
    '' \
    '[Install]' \
    'WantedBy=timers.target' |
    ssh "${ssh_options[@]}" "root@$node" \
      'install -m 0644 -o root -g root /dev/stdin /etc/systemd/system/openbao-backup.timer'

  ssh "${ssh_options[@]}" "root@$node" \
    'systemctl daemon-reload; systemctl enable --now openbao-backup.timer >/dev/null'
done

# Exercise every member. Standbys intentionally return success after the
# leader check; exactly one active member uploads the application-consistent
# snapshot to the immutable bucket.
for node in $OPENBAO_NODES; do
  ssh "${ssh_options[@]}" "root@$node" \
    'systemctl start openbao-backup.service; systemctl --quiet is-failed openbao-backup.service && exit 1 || true'
done

echo "OpenBao snapshot timers installed and the leader upload gate passed"
