{
  description = "Homelab NixOS guests (Proxmox LXC + VMs). Terraform creates the machines; this flake configures them.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

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
    inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      mkHost =
        name:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/${name} ];
        };
    in
    {
      nixosConfigurations = {
        nixtest01 = mkHost "nixtest01";
        nixbuild01 = mkHost "nixbuild01";
      };
    };
}
