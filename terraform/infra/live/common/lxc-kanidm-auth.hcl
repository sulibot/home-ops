locals {
  # Shared Kanidm UNIX auth client bootstrap for LXC service roles.
  # Configure the native unixd client once so service roles stay consistent.
  kanidm_unix_auth_commands = [
    "mkdir -p /etc/kanidm",
    "chmod 755 /etc/kanidm",
    "apt-get install -y -qq --no-install-recommends kanidm-unixd-clients >/dev/null 2>&1 || apt-get install -y -qq --no-install-recommends kanidm-unixd >/dev/null",
    "cat > /etc/kanidm/config <<'CFG'\nuri = \"https://idm.sulibot.com\"\nCFG",
    "cat > /etc/kanidm/unixd <<'CFG'\nversion = \"2\"\n[kanidm]\npam_allowed_login_groups = [\"posix_group\"]\nCFG",
    "chmod 600 /etc/kanidm/config /etc/kanidm/unixd",
    "systemctl enable --now kanidm-unixd >/dev/null 2>&1 || true",
    "systemctl enable --now kanidm-unixd-tasks >/dev/null 2>&1 || true",
  ]
}
