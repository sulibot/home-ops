# Common NixOS configuration for all VMs
{ config, pkgs, ... }:

{
  # Boot loader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # Enable QEMU guest agent
  services.qemuGuest.enable = true;

  # Networking
  networking.useDHCP = false;
  networking.useNetworkd = true;

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Time zone
  time.timeZone = "UTC";

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
    tmux
    jq
  ];

  # Enable nix flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Auto upgrade
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
  };

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken.
  system.stateVersion = "24.11";
}
