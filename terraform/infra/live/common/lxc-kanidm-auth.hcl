locals {
  # Shared Kanidm UNIX auth client bootstrap for LXC service roles.
  # Configure the native unixd client once so service roles stay consistent.
  #
  # kanidm_login_group is a single flat allow-list today (ENG-349 tracks
  # replacing it with host-class-specific login groups once the group
  # catalog in docs/architecture is written - until then, every consumer
  # of this file should read the value from here rather than repeating the
  # literal, so that decision only has to land in one place).
  kanidm_login_group = "posix_group"

  kanidm_unix_auth_commands = [
    "mkdir -p /etc/kanidm",
    "chmod 755 /etc/kanidm",
    "apt-get install -y -qq --no-install-recommends kanidm-unixd-clients >/dev/null 2>&1 || apt-get install -y -qq --no-install-recommends kanidm-unixd >/dev/null",
    "cat > /etc/kanidm/config <<'CFG'\nuri = \"https://idm.sulibot.com\"\nCFG",
    "cat > /etc/kanidm/unixd <<'CFG'\nversion = \"2\"\n[kanidm]\npam_allowed_login_groups = [\"${local.kanidm_login_group}\"]\nCFG",
    "chmod 600 /etc/kanidm/config /etc/kanidm/unixd",
    "systemctl enable --now kanidm-unixd >/dev/null 2>&1 || true",
    "systemctl enable --now kanidm-unixd-tasks >/dev/null 2>&1 || true",
  ]
}
