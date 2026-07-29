#!/usr/bin/env bash
# Validate and stream a least-privilege GCP KMS principal from 1Password to
# OpenBao nodes without placing its values in Terraform configuration or state.
set -euo pipefail

mode="${1:-sync}"
required_env=(
  OPENBAO_GCP_KMS_1PASSWORD_ITEM
  OPENBAO_GCP_KMS_1PASSWORD_VAULT
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

if ! command -v op >/dev/null 2>&1; then
  echo "1Password CLI (op) is required" >&2
  exit 1
fi

gcp_credentials="$(
  op document get "$OPENBAO_GCP_KMS_1PASSWORD_ITEM" \
    --vault "$OPENBAO_GCP_KMS_1PASSWORD_VAULT" 2>/dev/null || true
)"
if [[ -z "$gcp_credentials" ]]; then
  for label in service_account_json credentials credential password; do
    gcp_credentials="$(
      op item get "$OPENBAO_GCP_KMS_1PASSWORD_ITEM" \
        --vault "$OPENBAO_GCP_KMS_1PASSWORD_VAULT" \
        --fields "label=$label" \
        --reveal 2>/dev/null || true
    )"
    [[ -n "$gcp_credentials" ]] && break
  done
fi

if ! printf '%s' "$gcp_credentials" |
  jq -e '
    .type == "service_account" and
    (.project_id | type == "string" and length > 0) and
    (.client_email | type == "string" and length > 0) and
    (.private_key | type == "string" and length > 0)
  ' >/dev/null; then
  echo "1Password item must contain a valid GCP service-account JSON document" >&2
  exit 1
fi

credential_project="$(printf '%s' "$gcp_credentials" | jq -r '.project_id')"
if [[ "$credential_project" != "$OPENBAO_GCP_KMS_PROJECT_ID" ]]; then
  echo "GCP credential project does not match OPENBAO_GCP_KMS_PROJECT_ID" >&2
  exit 1
fi

if [[ "$mode" == "check" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    temp_dir="$(mktemp -d)"
    trap 'rm -r -- "$temp_dir"' EXIT
    install -m 0600 /dev/null "$temp_dir/credentials.json"
    printf '%s' "$gcp_credentials" >"$temp_dir/credentials.json"
    CLOUDSDK_CONFIG="$temp_dir/gcloud" \
      gcloud auth activate-service-account \
        --key-file="$temp_dir/credentials.json" \
        --project="$OPENBAO_GCP_KMS_PROJECT_ID" \
        --quiet >/dev/null
    CLOUDSDK_CONFIG="$temp_dir/gcloud" \
      gcloud kms keys describe "$OPENBAO_GCP_KMS_CRYPTO_KEY" \
        --project="$OPENBAO_GCP_KMS_PROJECT_ID" \
        --location="$OPENBAO_GCP_KMS_LOCATION" \
        --keyring="$OPENBAO_GCP_KMS_KEY_RING" \
        --quiet >/dev/null
    echo "validated the OpenBao GCP KMS key and 1Password principal"
  else
    echo "validated the OpenBao GCP KMS service account in 1Password"
    echo "gcloud is unavailable; the nodes will perform the KMS permission check"
  fi
  exit 0
fi

if [[ "$mode" != "sync" ]]; then
  echo "usage: $0 [check|sync]" >&2
  exit 1
fi
if [[ -z "${OPENBAO_NODES:-}" || -z "${OPENBAO_DOMAIN:-}" ]]; then
  echo "OPENBAO_NODES and OPENBAO_DOMAIN are required for sync" >&2
  exit 1
fi
if ! command -v ssh >/dev/null 2>&1; then
  echo "ssh is required" >&2
  exit 1
fi

ssh_opts=(
  -i "${OPENBAO_SSH_PRIVATE_KEY:-$HOME/.ssh/id_ed25519}"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

for node in $OPENBAO_NODES; do
  printf '%s\n' "$gcp_credentials" |
    ssh "${ssh_opts[@]}" "root@$node" \
      "install -m 0640 -o root -g openbao /dev/stdin /etc/openbao/gcp-kms-credentials.json"

  ssh "${ssh_opts[@]}" "root@$node" \
    "systemctl daemon-reload &&
     systemctl enable openbao.service >/dev/null &&
     systemctl restart openbao.service"

  ready=false
  for _ in $(seq 1 60); do
    status="$(
      curl --silent --insecure --max-time 2 \
        --resolve "$OPENBAO_DOMAIN:443:$node" \
        "https://$OPENBAO_DOMAIN/v1/sys/seal-status" || true
    )"
    if [[ "$(printf '%s' "$status" | jq -r '.type // empty')" == "gcpckms" ]]; then
      initialized="$(printf '%s' "$status" | jq -r '.initialized // false')"
      sealed="$(printf '%s' "$status" | jq -r '.sealed // true')"
      if [[ "$initialized" == "false" || "$sealed" == "false" ]]; then
        ready=true
        break
      fi
    fi
    sleep 2
  done

  if [[ "$ready" != "true" ]]; then
    echo "OpenBao on $node did not start with the GCP KMS seal" >&2
    ssh "${ssh_opts[@]}" "root@$node" \
      "journalctl --no-pager --unit openbao.service --lines 50" >&2 || true
    exit 1
  fi
done

echo "OpenBao GCP KMS credentials synchronized; all nodes passed seal-status"
