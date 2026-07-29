#!/usr/bin/env bash
# Reconcile an initialized OpenBao cluster one member at a time. Normal
# Terragrunt provisioning intentionally refuses initialized config changes.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
provision_script="$script_dir/provision.sh"
nodes=(10.100.0.68 10.100.0.69 10.100.0.70)
domain="openbao.sulibot.com"

ssh_options=(
  -i "$HOME/.ssh/id_ed25519"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

node_health() {
  local node="$1"
  curl --silent --show-error --fail --max-time 5 \
    --resolve "$domain:443:$node" \
    "https://$domain/v1/sys/health?standbyok=true&perfstandbyok=true"
}

healthy_members() {
  local count=0
  local node health
  for node in "${nodes[@]}"; do
    health="$(node_health "$node" 2>/dev/null || true)"
    if [[ "$(jq -r '.initialized == true' <<<"$health" 2>/dev/null)" == "true" ]] &&
      [[ "$(jq -r '.sealed == false' <<<"$health" 2>/dev/null)" == "true" ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

leader=""
standbys=()
for node in "${nodes[@]}"; do
  health="$(node_health "$node")"
  if [[ "$(jq -r '.initialized' <<<"$health")" != "true" ]] ||
    [[ "$(jq -r '.sealed' <<<"$health")" != "false" ]]; then
    echo "member $node is not initialized and unsealed" >&2
    exit 1
  fi
  if [[ "$(jq -r '.standby' <<<"$health")" == "false" ]]; then
    leader="$node"
  else
    standbys+=("$node")
  fi
done

if [[ -z "$leader" || "${#standbys[@]}" -ne 2 ]]; then
  echo "expected one leader and two standbys" >&2
  exit 1
fi

ordered_nodes=("${standbys[@]}" "$leader")
for node in "${ordered_nodes[@]}"; do
  if [[ "$(healthy_members)" -lt 3 ]]; then
    echo "refusing to restart $node before all three members are healthy" >&2
    exit 1
  fi

  echo "reconciling OpenBao member $node"
  ssh "${ssh_options[@]}" "root@$node" \
    "install -m 0750 /dev/stdin /usr/local/sbin/openbao-provision" \
    <"$provision_script"

  # Values in this fixed environment block are intentionally expanded locally.
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$node" \
    "env \
      OPENBAO_VERSION='2.6.1' \
      OPENBAO_SHA256='07fcc56ab6dc422a6a8b69b1cb6c1d20ada81edb86cfce428e35e9eab4799c9f' \
      OPENBAO_TENANT='100' \
      OPENBAO_DOMAIN='$domain' \
      OPENBAO_BASE_DOMAIN='sulibot.com' \
      OPENBAO_VIP4='10.100.240.67' \
      OPENBAO_VIP6='fd00:100:0:240::67' \
      OPENBAO_PEERS4='10.100.0.68 10.100.0.69 10.100.0.70' \
      OPENBAO_BGP_PEER4='10.100.0.254' \
      OPENBAO_BGP_PEER6='fd00:100::fffe' \
      OPENBAO_BGP_PEER_AS='4200001000' \
      OPENBAO_SEAL_TYPE='gcpckms' \
      OPENBAO_GCP_KMS_PROJECT_ID='sulibot-openbao-kms' \
      OPENBAO_GCP_KMS_LOCATION='global' \
      OPENBAO_GCP_KMS_KEY_RING='openbao' \
      OPENBAO_GCP_KMS_CRYPTO_KEY='auto-unseal' \
      OPENBAO_AUDIT_SYSLOG_HOST='10.101.250.125' \
      OPENBAO_AUDIT_SYSLOG_PORT='2515' \
      OPENBAO_ALLOW_INITIALIZED_CONFIG_CHANGE='true' \
      /usr/local/sbin/openbao-provision"

  # Recover safely if a prior reconcile installed the config but stopped
  # before OpenBao restarted (for example, a host-service validation error).
  ssh "${ssh_options[@]}" "root@$node" \
    "ss -ltn '( sport = :9101 )' | grep -q ':9101' || systemctl restart openbao.service"

  ready=false
  for _ in $(seq 1 60); do
    health="$(node_health "$node" 2>/dev/null || true)"
    if [[ "$(jq -r '.initialized == true' <<<"$health" 2>/dev/null)" == "true" ]] &&
      [[ "$(jq -r '.sealed == false' <<<"$health" 2>/dev/null)" == "true" ]]; then
      ready=true
      break
    fi
    sleep 2
  done
  if [[ "$ready" != "true" ]]; then
    echo "member $node did not return initialized and unsealed" >&2
    exit 1
  fi

  metrics="$(
    curl --silent --show-error --fail --max-time 5 \
      --resolve "$domain:9101:$node" \
      "https://$domain:9101/v1/sys/metrics?format=prometheus"
  )"
  grep -q '^# HELP' <<<"$metrics"
done

if [[ "$(healthy_members)" -ne 3 ]]; then
  echo "cluster did not finish with three healthy members" >&2
  exit 1
fi

curl --silent --show-error --fail --max-time 5 \
  "https://$domain/v1/sys/health" |
  jq -e '.initialized == true and .sealed == false' >/dev/null

echo "OpenBao rolling reconciliation completed with three healthy members"
