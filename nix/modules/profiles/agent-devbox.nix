# Persistent, low-idle-footprint development coordinator. Expensive database
# and browser verification belongs on isolated runners rather than this guest.
{ pkgs, unstablePkgs, ... }:
{
  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    nix-ld.enable = true;
    ssh.knownHosts.github = {
      hostNames = [ "github.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
    zsh.enable = true;
  };

  users.users.agent = {
    isNormalUser = true;
    description = "Agent development coordinator";
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com"
    ];
  };

  security.sudo.extraRules = [
    {
      users = [ "agent" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  nix.settings = {
    auto-optimise-store = true;
    max-jobs = 2;
    cores = 2;
  };

  environment.systemPackages = with pkgs; [
    unstablePkgs.codex
    unstablePkgs.claude-code
    corepack
    curl
    fd
    fzf
    gcc
    gh
    git-lfs
    gnumake
    jq
    kubectl
    kubernetes-helm
    kustomize
    nodejs_24
    openssl
    pkg-config
    postgresql_17
    python3
    ripgrep
    rsync
    tmux
    yq-go
  ];
}
