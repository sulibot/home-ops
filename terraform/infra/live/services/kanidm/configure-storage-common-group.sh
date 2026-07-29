#!/usr/bin/env bash
# Reconcile the canonical POSIX entitlement for the organization-owned common
# file space. Authentication is interactive through the existing 1Password
# item; no credential is written to the repository or OpenTofu state.
set -euo pipefail

kanidm_host="${KANIDM_HOST:-10.100.0.61}"
group_name="${COMMON_GROUP:-storage_common_rw}"
initial_member="${COMMON_INITIAL_MEMBER:-sulibot}"
expected_user_gid="${EXPECTED_USER_GID:-1888405477}"
expected_common_gid="${EXPECTED_COMMON_GID:-1965604563}"
ssh_key="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
ssh_opts=(-i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

if ! op whoami >/dev/null 2>&1; then
  echo "1Password CLI is not authenticated; run 'eval \$(op signin)' and retry." >&2
  exit 1
fi

admin_password="$(op item get kanidm --vault Kubernetes --fields password --reveal)"
admin_password_b64="$(printf '%s' "${admin_password}" | base64)"
unset admin_password

ssh "${ssh_opts[@]}" "root@${kanidm_host}" \
  "ADMIN_PASSWORD_B64='${admin_password_b64}' GROUP_NAME='${group_name}' INITIAL_MEMBER='${initial_member}' EXPECTED_USER_GID='${expected_user_gid}' EXPECTED_COMMON_GID='${expected_common_gid}' bash -s" <<'REMOTE'
set -euo pipefail
export KANIDM_URL="https://127.0.0.1:8443"
export KANIDM_SKIP_HOSTNAME_VERIFICATION=true
export KANIDM_ACCEPT_INVALID_CERTS=true
export ADMIN_PASSWORD="$(printf '%s' "${ADMIN_PASSWORD_B64}" | base64 -d)"
unset ADMIN_PASSWORD_B64

command -v expect >/dev/null 2>&1 ||
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq expect

expect <<'EXPECT'
set timeout 20
spawn kanidm login --name idm_admin
expect -re "(?i)password:"
send -- "$env(ADMIN_PASSWORD)\r"
expect eof
EXPECT
unset ADMIN_PASSWORD

kanidm group get "${GROUP_NAME}" --name idm_admin >/dev/null 2>&1 ||
  kanidm group create "${GROUP_NAME}" --name idm_admin
kanidm group set-description "${GROUP_NAME}" \
  "Canonical POSIX write entitlement for the organization-owned Common file space" \
  --name idm_admin
kanidm group posix set "${GROUP_NAME}" --name idm_admin
kanidm group add-members "${GROUP_NAME}" "${INITIAL_MEMBER}" --name idm_admin || true
kanidm person posix show "${INITIAL_MEMBER}" --name idm_admin >/dev/null 2>&1 ||
  kanidm person posix set "${INITIAL_MEMBER}" --shell /bin/bash --name idm_admin

person_posix="$(kanidm person posix show "${INITIAL_MEMBER}" --name idm_admin)"
group_posix="$(kanidm group posix show "${GROUP_NAME}" --name idm_admin)"
actual_user_gid="$(awk '/^gidnumber:/ {print $2; exit}' <<<"${person_posix}")"
actual_common_gid="$(
  sed -n 's/.*gidnumber":[[:space:]]*\([0-9][0-9]*\).*/\1/p' <<<"${group_posix}"
)"
test "${actual_user_gid}" = "${EXPECTED_USER_GID}"
test "${actual_common_gid}" = "${EXPECTED_COMMON_GID}"

printf '%s\n' "${person_posix}"
printf '%s\n' "${group_posix}"
kanidm group list-members "${GROUP_NAME}" --name idm_admin
REMOTE
