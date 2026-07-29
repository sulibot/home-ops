#!/usr/bin/env bash
set -euo pipefail

: "${OPENBAO_ROLE_ID:?OPENBAO_ROLE_ID is required}"
: "${OPENBAO_SECRET_ID:?OPENBAO_SECRET_ID is required}"
: "${B2_S3_ENDPOINT:?B2_S3_ENDPOINT is required}"
: "${B2_REGION:?B2_REGION is required}"
: "${B2_INFRA_BUCKET:?B2_INFRA_BUCKET is required}"
: "${B2_INFRA_ACCESS_KEY_ID:?B2_INFRA_ACCESS_KEY_ID is required}"
: "${B2_INFRA_APPLICATION_KEY:?B2_INFRA_APPLICATION_KEY is required}"

export BAO_ADDR="https://$(hostname -s).sulibot.com"
export VAULT_ADDR="$BAO_ADDR"
export BAO_TOKEN="$(
  bao write -format=json auth/approle/login \
    role_id="$OPENBAO_ROLE_ID" \
    secret_id="$OPENBAO_SECRET_ID" |
    jq -er '.auth.client_token'
)"
export VAULT_TOKEN="$BAO_TOKEN"

# The timer runs on every member for redundancy. Only the current leader
# creates a snapshot; standby executions finish successfully without writing.
if ! bao read -format=json sys/leader |
  jq -e '.data.is_self == true' >/dev/null; then
  echo "$(hostname -s) is not the active OpenBao leader; snapshot skipped"
  exit 0
fi

install -d -m 0700 /var/backups/openbao
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
snapshot="/var/backups/openbao/openbao-${timestamp}-$(hostname -s).snap"

bao operator raft snapshot save "$snapshot"
test -s "$snapshot"
validation_dir="$(mktemp -d)"
trap 'rm -rf "$validation_dir"' EXIT
tar -xzf "$snapshot" -C "$validation_dir"
(
  cd "$validation_dir"
  sha256sum --check SHA256SUMS >/dev/null
)

export RCLONE_CONFIG_B2_TYPE=s3
export RCLONE_CONFIG_B2_PROVIDER=Other
export RCLONE_CONFIG_B2_ACCESS_KEY_ID="$B2_INFRA_ACCESS_KEY_ID"
export RCLONE_CONFIG_B2_SECRET_ACCESS_KEY="$B2_INFRA_APPLICATION_KEY"
export RCLONE_CONFIG_B2_ENDPOINT="$B2_S3_ENDPOINT"
export RCLONE_CONFIG_B2_REGION="$B2_REGION"

remote="b2:${B2_INFRA_BUCKET}/openbao/raft/$(basename "$snapshot")"
rclone copyto \
  "$snapshot" \
  "$remote" \
  --s3-no-check-bucket \
  --check-first \
  --log-level=INFO

local_bytes="$(stat -c %s "$snapshot")"
remote_bytes="$(
  rclone size "$remote" \
    --s3-no-check-bucket \
    --json |
    jq -er '.bytes'
)"
if [ "$local_bytes" -ne "$remote_bytes" ]; then
  echo "OpenBao snapshot remote byte count does not match local file" >&2
  exit 1
fi

find /var/backups/openbao \
  -type f \
  -name 'openbao-*.snap' \
  -mtime +7 \
  -delete

echo "OpenBao Raft snapshot uploaded: object=openbao/raft/$(basename "$snapshot") bytes=$remote_bytes"
