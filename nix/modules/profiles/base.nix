# Baseline for every homelab NixOS guest, LXC or VM.
{ lib, pkgs, ... }:
let
  # Cross-toolchain site facts (edit site.yaml at the repo root, then run
  # scripts/sync-site-facts.sh)
  site = builtins.fromJSON (builtins.readFile ../../site.json);
in
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  time.timeZone = "America/Los_Angeles";

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com"
  ];

  networking.nameservers = [
    site.dns_servers.ipv6
    site.dns_servers.ipv4
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    dig
  ];

  networking.firewall.enable = true; # SSH is allowed by default

  # Deploys come from the repo via: nixos-rebuild switch --flake .#<host> \
  #   --target-host root@<host> --build-host root@<host>
  system.stateVersion = lib.mkDefault "25.11";
}
