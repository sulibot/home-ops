#!/usr/bin/env bash
# Onboard a Kanidm person by tier. Executes the real kanidm commands by
# default over SSH to a Kanidm node; pass --dry-run to only print the
# commands it would run without running them.
#
# Run by hand - deliberately NOT part of any `terraform apply`. Person and
# group-membership lifecycle is a `kanidm` concern, not Terraform's (see
# docs/tickets/kanidm-onboard-user-groups.md, and the "Evaluated and
# rejected" section of docs/tickets/kanidm-oidc-source-for-authentik.md for
# why this isn't a Terraform-provider resource either).
#
# Usage:
#   ./onboard-user.sh <username> "<display name>" <tier> [gidnumber] [--dry-run]
#
# Tiers (see docs/tickets/kanidm-onboard-user-groups.md for the reasoning):
#   tier-admin     full infra + app admin (you)
#   tier-trusted   more than consumer access, not infra admin (e.g. wife,
#                  family member: finance app, CloudBeaver, Filebrowser)
#   tier-standard  consumer-only: apps, no SSH, no admin, no finance/raw-data
#                  tools (e.g. friend)
#
# Service/machine identities are NOT covered here - those are Kanidm service
# accounts (`kanidm service-account create`), never a person in a human
# group.
#
# Every command this script runs is printed before it runs, whether or not
# --dry-run is given - the only difference --dry-run makes is whether the
# command actually executes.
#
# Requires (unless --dry-run): 1Password CLI authenticated (reads the
# "kanidm" item's idm_admin password) and SSH access to the Kanidm nodes.

set -euo pipefail

kanidm_node="${KANIDM_BOOTSTRAP_NODE:-10.100.0.61}"
onepassword_vault="${KANIDM_1PASSWORD_VAULT:-Kubernetes}"
known_tiers="tier-admin tier-trusted tier-standard"
dry_run=false

usage() {
  echo "Usage: $0 <username> \"<display name>\" <tier> [gidnumber] [--dry-run]" >&2
  echo "Known tiers: $known_tiers" >&2
  exit 1
}

username=""
display_name=""
tier=""
gidnumber=""
positional=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    *) positional+=("$arg") ;;
  esac
done

username="${positional[0]:-}"
display_name="${positional[1]:-}"
tier="${positional[2]:-}"
gidnumber="${positional[3]:-}"

[[ -n "$username" && -n "$display_name" && -n "$tier" ]] || usage
[[ "$username" =~ ^[a-z][a-z0-9_.-]*$ ]] || {
  echo "refusing an unsafe username: $username" >&2
  exit 1
}

case "$tier" in
  tier-admin)
    groups="posix_group infrastructure-users trusted-users standard-users openbao-admins opencloud-admins"
    ;;
  tier-trusted)
    groups="trusted-users standard-users opencloud-users"
    ;;
  tier-standard)
    groups="standard-users opencloud-users"
    ;;
  *)
    echo "Unknown tier '$tier'. Known tiers: $known_tiers" >&2
    exit 1
    ;;
esac

# Build the ordered command list as a plain array of strings - one per
# `kanidm` invocation, run in the same authenticated CLI session.
commands=("kanidm person create '$username' '$display_name' --name idm_admin")
if [[ " $groups " == *" posix_group "* ]]; then
  commands+=("kanidm person posix set '$username'${gidnumber:+ --gidnumber $gidnumber} --name idm_admin")
else
  commands+=("# (skipped: $tier does not include posix_group - no SSH/Unix login for this person)")
fi
for group in $groups; do
  commands+=("kanidm group add-members '$group' '$username' --name idm_admin")
done

echo "Plan for '$username' ($display_name), tier '$tier':"
for cmd in "${commands[@]}"; do
  echo "  $cmd"
done
echo
echo "Not included above (run once, separately, after this - it needs its"
echo "own interactive review since it prints a one-time recovery secret):"
echo "  kanidmd -c /etc/kanidmd/server.toml scripting recover-account '$username'"
echo

if [[ "$dry_run" == "true" ]]; then
  echo "--dry-run: not executing."
  exit 0
fi

op whoami >/dev/null
admin_password="$(op item get kanidm --vault "$onepassword_vault" --fields label=password --reveal)"
[[ -n "$admin_password" ]] || {
  echo "could not read the Kanidm idm_admin credential from 1Password" >&2
  exit 1
}

ssh_options=(
  -i "${KANIDM_SSH_KEY:-$HOME/.ssh/id_ed25519}"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

remote_script="$(
  {
    echo "set -euo pipefail"
    echo "export KANIDM_URL=https://127.0.0.1:8443"
    echo "export KANIDM_SKIP_HOSTNAME_VERIFICATION=true"
    echo "export KANIDM_ACCEPT_INVALID_CERTS=true"
    echo "which expect >/dev/null 2>&1 || apt-get install -y -qq expect"
    printf 'expect -c "\nset timeout 15\nspawn kanidm login --name idm_admin\nexpect \\"Password:\\"\nsend \\"%s\\\\r\\"\nexpect eof\n"\n' "$admin_password"
    for cmd in "${commands[@]}"; do
      [[ "$cmd" == \#* ]] && continue
      echo "echo '+ $cmd'"
      echo "$cmd"
    done
  }
)"
unset admin_password

ssh "${ssh_options[@]}" "root@$kanidm_node" bash -s <<<"$remote_script"

echo
echo "Done. Recover a credential for '$username' separately with:"
echo "  ssh root@$kanidm_node kanidmd -c /etc/kanidmd/server.toml scripting recover-account '$username'"
