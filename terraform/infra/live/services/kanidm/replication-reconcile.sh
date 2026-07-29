#!/usr/bin/env bash
# Reconcile the three-node Kanidm topology with node01 as the seed authority.
set -euo pipefail
on_error() {
  local code="$1"
  local line="$2"
  echo "Kanidm replication reconciliation failed at line $line (exit $code)" >&2
  exit "$code"
}
trap 'on_error "$?" "$LINENO"' ERR

primary="10.100.0.61"
secondaries=("10.100.0.62" "10.100.0.63")
nodes=("$primary" "${secondaries[@]}")
ssh_options=(
  -i "${KANIDM_SSH_KEY:-$HOME/.ssh/id_ed25519}"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

remote() {
  local node="$1"
  shift
  # The remaining arguments are the intentionally constructed remote command.
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$node" "$@"
}

replication_certificate() {
  local node="$1"
  remote "$node" \
    "kanidmd show-replication-certificate -c /etc/kanidmd/server.toml 2>&1" |
    sed -n 's/.*certificate: "\([^"]*\)".*/\1/p' |
    tail -n1
}

domain_uuid() {
  local node="$1"
  remote "$node" \
    "kanidmd domain show -c /etc/kanidmd/server.toml 2>/dev/null" |
    sed -nE 's/.*domain_uuid[[:space:]]*:[[:space:]]*//p' |
    head -n1
}

write_config() {
  local node="$1"
  local content="$2"
  printf '%s\n' "$content" |
    remote "$node" \
      "install -o root -g kanidmd -m 640 /dev/stdin /etc/kanidmd/server.toml"
}

configuration() {
  local self="$1"
  local peer1="$2"
  local peer1_certificate="$3"
  local peer2="$4"
  local peer2_certificate="$5"
  local automatic_refresh=""
  if [[ "$self" != "$primary" && "$peer1" == "$primary" ]]; then
    automatic_refresh="automatic_refresh = true"
  fi

  cat <<EOF
version = "2"
log_level = "debug"
# Managed by Terraform and replication-reconcile.sh.
bindaddress = "[::]:8443"
ldapbindaddress = "[::]:3636"
domain = "idm.sulibot.com"
origin = "https://idm.sulibot.com"
db_path = "/var/lib/kanidm/kanidm.db"
role = "WriteReplica"
tls_chain = "/etc/kanidmd/chain.pem"
tls_key = "/etc/kanidmd/key.pem"

[replication]
origin = "repl://$self:8444"
bindaddress = "[::]:8444"

[replication."repl://$peer1:8444"]
type = "mutual-pull"
partner_cert = "$peer1_certificate"
$automatic_refresh

[replication."repl://$peer2:8444"]
type = "mutual-pull"
partner_cert = "$peer2_certificate"
EOF
}

for node in "${nodes[@]}"; do
  [[ "$(remote "$node" "systemctl is-active kanidmd")" == "active" ]]
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
for node in "${secondaries[@]}"; do
  snapshot="/var/backups/kanidm/snapshots/pre-replication-reseed-$timestamp.db"
  remote "$node" \
    "install -d -o root -g kanidmd -m 750 /var/backups/kanidm/snapshots && sqlite3 /var/lib/kanidm/kanidm.db \".backup '$snapshot'\" && chmod 640 '$snapshot'"
  echo "Created recoverable pre-reseed snapshot on $node: $snapshot"
done

certificate61="$(replication_certificate 10.100.0.61)"
certificate62="$(replication_certificate 10.100.0.62)"
certificate63="$(replication_certificate 10.100.0.63)"
[[ -n "$certificate61" && -n "$certificate62" && -n "$certificate63" ]]

write_config 10.100.0.61 \
  "$(configuration 10.100.0.61 10.100.0.62 "$certificate62" 10.100.0.63 "$certificate63")"
write_config 10.100.0.62 \
  "$(configuration 10.100.0.62 10.100.0.61 "$certificate61" 10.100.0.63 "$certificate63")"
write_config 10.100.0.63 \
  "$(configuration 10.100.0.63 10.100.0.61 "$certificate61" 10.100.0.62 "$certificate62")"
unset certificate61 certificate62 certificate63

# Start consumers first, then make the canonical primary aware of them.
for node in "${secondaries[@]}" "$primary"; do
  remote "$node" \
    "kanidmd configtest -c /etc/kanidmd/server.toml >/dev/null && systemctl restart kanidmd && systemctl is-active --quiet kanidmd"
done

sleep 5
primary_uuid="$(domain_uuid "$primary")"
for node in "${secondaries[@]}"; do
  if [[ "$(domain_uuid "$node")" != "$primary_uuid" ]]; then
    remote "$node" \
      "kanidmd refresh-replication-consumer --config-path /etc/kanidmd/server.toml --i-want-to-refresh-this-servers-database"
  fi
done

for attempt in {1..20}; do
  uuid61="$(domain_uuid 10.100.0.61)"
  uuid62="$(domain_uuid 10.100.0.62)"
  uuid63="$(domain_uuid 10.100.0.63)"
  if [[ -n "$uuid61" && "$uuid61" == "$uuid62" && "$uuid62" == "$uuid63" ]]; then
    break
  fi
  if [[ "$attempt" -eq 20 ]]; then
    echo "Kanidm domain UUIDs did not converge" >&2
    exit 1
  fi
  sleep 3
done

for node in "${nodes[@]}"; do
  curl --silent --show-error --fail \
    --resolve "idm.sulibot.com:8443:$node" \
    "https://idm.sulibot.com:8443/oauth2/openid/openbao/.well-known/openid-configuration" \
    >/dev/null
done

echo "Kanidm replication converged on the canonical node01 database"
