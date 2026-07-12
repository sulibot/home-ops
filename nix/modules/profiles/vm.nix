# Proxmox VM guests. First install lands via nixos-anywhere
# (--build-on-remote), which uses the host's disko layout; afterwards
# it's ordinary nixos-rebuild --target-host.
{ inputs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    inputs.disko.nixosModules.disko
    ./base.nix
  ];

  services.qemuGuest.enable = true;

  boot.loader.grub = {
    enable = true;
    efiSupport = false;
  };

  # Serial console so the Proxmox console works (matches VGA-less VM pattern)
  boot.kernelParams = [ "console=ttyS0,115200" ];
}
