#!/usr/bin/env bash
set -euo pipefail

: "${BACKUP_PATH:?BACKUP_PATH is required}"
: "${KOPIA_HOSTNAME:?KOPIA_HOSTNAME is required}"
: "${KOPIA_USERNAME:?KOPIA_USERNAME is required}"
: "${BACKUP_DESCRIPTION:?BACKUP_DESCRIPTION is required}"

if [[ "$KOPIA_REPOSITORY" =~ ^s3://([^/]+)(/(.*))?$ ]]; then
  bucket="${BASH_REMATCH[1]}"
  prefix="${BASH_REMATCH[3]}"
else
  echo "Unsupported KOPIA_REPOSITORY format: $KOPIA_REPOSITORY" >&2
  exit 1
fi

endpoint="$KOPIA_S3_ENDPOINT"
endpoint_scheme="https"
endpoint_path=""
if [[ "$endpoint" =~ ^(https?)://([^/]+)(/(.*))?$ ]]; then
  endpoint_scheme="${BASH_REMATCH[1]}"
  endpoint="${BASH_REMATCH[2]}"
  endpoint_path="${BASH_REMATCH[4]}"
fi

if [ -n "$endpoint_path" ]; then
  if [ -n "${prefix:-}" ]; then
    prefix="${endpoint_path%/}/${prefix}"
  else
    prefix="$endpoint_path"
  fi
fi
if [ -n "${prefix:-}" ] && [[ "$prefix" != */ ]]; then
  prefix="${prefix}/"
fi

connect_args=(
  "--bucket=$bucket"
  "--endpoint=$endpoint"
  "--access-key=$AWS_ACCESS_KEY_ID"
  "--secret-access-key=$AWS_SECRET_ACCESS_KEY"
  "--password=$KOPIA_PASSWORD"
  "--config-file=/tmp/kopia.config"
  "--override-hostname=$KOPIA_HOSTNAME"
  "--override-username=$KOPIA_USERNAME"
)
if [ -n "${prefix:-}" ]; then
  connect_args+=("--prefix=$prefix")
fi
if [ "$endpoint_scheme" = "http" ]; then
  connect_args+=("--disable-tls")
fi

echo "Connecting to bucket=$bucket endpoint=$endpoint prefix=${prefix:-<none>}"
kopia repository connect s3 "${connect_args[@]}"
kopia snapshot create "$BACKUP_PATH" \
  --config-file=/tmp/kopia.config \
  --description="$BACKUP_DESCRIPTION"
kopia snapshot list \
  "$KOPIA_USERNAME@$KOPIA_HOSTNAME:$BACKUP_PATH" \
  --config-file=/tmp/kopia.config |
  tail -n 10
