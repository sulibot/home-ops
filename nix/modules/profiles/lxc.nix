# Proxmox LXC guests. Create the CT with ostype=unmanaged, features
# nesting=1, from the NixOS proxmoxLXC template tarball
# (scripts/fetch-nixos-lxc-template.sh uploads it to resources:vztmpl).
{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./base.nix
  ];

  # PVE's console for unmanaged CTs attaches to /dev/console
  proxmoxLXC = {
    manageNetwork = true; # we set static addresses declaratively below/per-host
    privileged = false;
  };
}
