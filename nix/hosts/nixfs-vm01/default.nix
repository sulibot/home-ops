{ ... }:
{
  imports = [
    ../../modules/profiles/vm.nix
    ../../modules/profiles/user-storage-cephfs.nix
  ];

  networking = {
    hostName = "nixfs-vm01";
    useDHCP = false;
    interfaces.ens18 = {
      ipv4.addresses = [ { address = "10.200.0.203"; prefixLength = 24; } ];
      ipv6.addresses = [ { address = "fd00:200::203"; prefixLength = 64; } ];
      # Ceph messenger traffic must return through this VM's local PVE node.
      # The VLAN default gateway produced a valid TCP handshake but an
      # asymmetric messenger session that never completed.
      ipv6.routes = [
        {
          address = "fc00:20::";
          prefixLength = 64;
          via = "fd00:200::1";
        }
      ];
    };
    defaultGateway = { address = "10.200.0.254"; interface = "ens18"; };
    defaultGateway6 = { address = "fd00:200::fffe"; interface = "ens18"; };
  };

  disko.devices.disk.main = {
    device = "/dev/vda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = { size = "1M"; type = "EF02"; };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };
}
