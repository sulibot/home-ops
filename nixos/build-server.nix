# NixOS configuration for build server
# Used for building Talos extensions (i915-sriov) and other packages
{ config, pkgs, ... }:

{
  imports = [ ./common.nix ];

  networking.hostName = "nixos-build";

  # Build-specific packages
  environment.systemPackages = with pkgs; [
    # Kernel build tools
    gcc
    gnumake
    bc
    bison
    flex
    elfutils
    openssl
    perl
    python3

    # Container/OCI tools
    docker
    buildah
    skopeo
    crane

    # Development tools
    git
    gh
    nix-prefetch-git

    # Talos tools
    talosctl
    kubectl
  ];

  # Docker for building container images
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Increase build resources
  nix.settings = {
    max-jobs = "auto";
    cores = 0; # Use all available cores
    sandbox = true;
  };

  # Binary cache
  nix.settings.substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
  ];

  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
