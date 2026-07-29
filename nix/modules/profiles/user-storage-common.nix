# Common client-side contract for the shared user file plane.
#
# Kanidm supplies the POSIX identity. The shared files are deliberately
# mounted below the home directory rather than replacing the whole home.
{ pkgs, ... }:
{
  imports = [ ./kanidm-client.nix ];

  environment.systemPackages = with pkgs; [
    acl
    attr
    ceph
    python3
  ];

  systemd.tmpfiles.rules = [
    "d /home 0755 root root -"
    "d /home/sulibot 0700 1888405477 1888405477 -"
  ];
}
