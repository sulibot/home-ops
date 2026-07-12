# Pilot NixOS VM: x86_64 build server. Once live, point other machines'
# distributed builds here (nix.buildMachines) instead of building on each
# small guest.
{ ... }:
{
  imports = [ ../../modules/profiles/vm.nix ];

  networking = {
    hostName = "nixbuild01";
    useDHCP = false;
    interfaces.ens18 = {
      ipv4.addresses = [
        {
          address = "10.200.0.201";
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "fd00:200::201";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "10.200.0.254";
      interface = "ens18";
    };
    defaultGateway6 = {
      address = "fd00:200::fffe";
      interface = "ens18";
    };
  };

  # Builder role
  nix.settings.max-jobs = "auto";

  # Single-disk layout consumed by nixos-anywhere on first install
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # BIOS boot for grub
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
