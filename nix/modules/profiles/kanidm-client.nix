# Opt-in Kanidm Unix auth for NixOS guests (LXC/VM). Not imported by
# base.nix, so importing this is a per-host decision:
#
#   imports = [ ../../modules/profiles/base.nix ../../modules/profiles/kanidm-client.nix ];
#
# Mirrors the kanidm-unixd setup already used on Debian LXC/VM guests via
# terraform/infra/modules/kanidm_unixd_client, using this repo's pinned
# nixpkgs services.kanidm module (enableClient/enablePam - newer nixpkgs
# renamed these to client.enable/unix.enable, but this flake's pinned
# revision still uses the older flat option names).
#
# PAM stack wiring for interactive Kanidm password login is deliberately
# left out here - this module only registers the daemons + NSS databases.
# See docs/tickets/kanidm-unixd-lxc-vm-base-injection.md for why.
{ pkgs, ... }:
{
  services.kanidm = {
    # This flake's pinned nixpkgs defaults services.kanidm.package to
    # kanidm_1_4 (removed, EOL), and the unversioned pkgs.kanidm alias
    # (1.7.4) is also EOL/marked insecure - pin the current supported
    # version explicitly. Bump this alongside the live Kanidm server's
    # own version (see terraform/infra/live/services/kanidm).
    package = pkgs.kanidm_1_10;

    enableClient = true;
    clientSettings.uri = "https://idm.sulibot.com";

    enablePam = true;
    unixSettings.pam_allowed_login_groups = [ "posix_group" ];
  };
}
