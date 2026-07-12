# Pilot NixOS LXC: proves template -> terraform -> flake -> rebuild flow.
{ ... }:
{
  imports = [ ../../modules/profiles/lxc.nix ];

  networking = {
    hostName = "nixtest01";
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "10.200.0.202";
          prefixLength = 24;
        }
      ];
      ipv6.addresses = [
        {
          address = "fd00:200::202";
          prefixLength = 64;
        }
      ];
    };
    defaultGateway = {
      address = "10.200.0.254";
      interface = "eth0";
    };
    defaultGateway6 = {
      address = "fd00:200::fffe";
      interface = "eth0";
    };
  };
}
