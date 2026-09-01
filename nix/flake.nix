{
  description = "Homelab NixOS guests (Proxmox LXC + VMs). Terraform creates the machines; this flake configures them.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Agent CLIs release faster than the stable NixOS package set. Keeping
    # this separate lets the base operating system remain on 25.11.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, nixpkgs-unstable, ... }:
    let
      system = "x86_64-linux";
      unstablePkgs = import nixpkgs-unstable {
        inherit system;
        config.allowUnfreePredicate = package:
          builtins.elem (nixpkgs.lib.getName package) [ "claude-code" ];
      };
      mkHost =
        name:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs unstablePkgs; };
          modules = [ ./hosts/${name} ];
        };
    in
    {
      nixosConfigurations = {
        nixtest01 = mkHost "nixtest01";
        nixbuild01 = mkHost "nixbuild01";
        nixfs-vm01 = mkHost "nixfs-vm01";
        nixfs-lxc01 = mkHost "nixfs-lxc01";
        agent-devbox01 = mkHost "agent-devbox01";
      };
    };
}
