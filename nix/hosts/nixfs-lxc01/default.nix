{ ... }:
{
  imports = [
    ../../modules/profiles/lxc.nix
    ../../modules/profiles/user-storage-common.nix
  ];

  networking = {
    hostName = "nixfs-lxc01";
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [ { address = "10.200.0.204"; prefixLength = 24; } ];
      ipv6.addresses = [ { address = "fd00:200::204"; prefixLength = 64; } ];
    };
    defaultGateway = { address = "10.200.0.254"; interface = "eth0"; };
    defaultGateway6 = { address = "fd00:200::fffe"; interface = "eth0"; };
  };
}
