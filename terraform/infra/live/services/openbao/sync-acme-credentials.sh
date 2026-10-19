#!/usr/bin/env bash
# Stream the DNS-01 credential to each OpenBao member without placing it in
# Terraform inputs or state. Each member then owns its ACME renewal lifecycle.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
secrets_file="${OPENBAO_ACME_SECRETS_FILE:-$script_dir/../../common/secrets.sops.yaml}"
nodes_raw="${OPENBAO_NODES:-10.100.0.68 10.100.0.69 10.100.0.70}"

for command in sops jq ssh; do
  command -v "$command" >/dev/null || {
    echo "required command not found: $command" >&2
    exit 1
  }
done

secrets_json="$(sops --decrypt --output-type json "$secrets_file")"
cloudflare_token="$(jq -er '.cloudflare_api_token' <<<"$secrets_json")"
acme_email="$(jq -er '.acme_contact_email' <<<"$secrets_json")"
unset secrets_json

if [[ ! "$cloudflare_token" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "Cloudflare token contains unsupported characters" >&2
  exit 1
fi
if [[ ! "$acme_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then
  echo "invalid ACME contact email" >&2
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

credential="dns_cloudflare_api_token = $cloudflare_token"

read -r -a nodes <<<"$nodes_raw"
for index in "${!nodes[@]}"; do
  node="${nodes[$index]}"
  node_name="$(ssh "${ssh_options[@]}" "root@$node" 'hostname -s')"
  if [[ ! "$node_name" =~ ^openbao[0-9]+$ ]]; then
    echo "unexpected OpenBao hostname from $node: $node_name" >&2
    exit 1
  fi
  had_certificate=false
  if ssh "${ssh_options[@]}" "root@$node" \
    'test -s /etc/letsencrypt/live/openbao.sulibot.com/fullchain.pem'; then
    had_certificate=true
  fi
  printf '%s\n' "$credential" |
    ssh "${ssh_options[@]}" "root@$node" \
      'install -d -m 0700 -o root -g root /etc/letsencrypt && install -m 0600 -o root -g root /dev/stdin /etc/letsencrypt/cloudflare.ini'
  ssh "${ssh_options[@]}" "root@$node" \
    "certbot certonly --non-interactive --agree-tos --email '$acme_email' --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini --dns-cloudflare-propagation-seconds 60 --cert-name openbao.sulibot.com --domains openbao.sulibot.com --domains '$node_name.sulibot.com' --deploy-hook /usr/local/sbin/openbao-certbot-deploy"
  ssh "${ssh_options[@]}" "root@$node" \
    'RENEWED_LINEAGE=/etc/letsencrypt/live/openbao.sulibot.com /usr/local/sbin/openbao-certbot-deploy'
  if [[ "$had_certificate" == false ]] && ((index + 1 < ${#nodes[@]})); then
    sleep 150
  fi
done

unset credential cloudflare_token acme_email
echo "OpenBao ACME credentials synchronized and renewal checked on all members"
