# NixOS configuration for Kanidm identity server
# Kanidm: Modern identity management and authentication
{ config, pkgs, lib, ... }:

{
  imports = [ ./common.nix ];

  # Kanidm service
  services.kanidm = {
    enableServer = true;
    package = pkgs.kanidm;

    serverSettings = {
      # Will be overridden by Terragrunt per-node config
      domain = "kanidm.example.com";
      origin = "https://kanidm.example.com";

      # Database location
      db_path = "/var/lib/kanidm/kanidm.db";

      # TLS will be handled by external reverse proxy (Traefik/Nginx)
      bindaddress = "0.0.0.0:8443";

      # Replication settings (for HA cluster)
      # replication_origin = "https://kanidm01.example.com:8444";
      # replication_bind_address = "0.0.0.0:8444";
    };
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      8443  # Kanidm HTTPS
      8444  # Kanidm replication (internal)
    ];
  };

  # PostgreSQL for Kanidm (optional, uses SQLite by default)
  # Uncomment if using PostgreSQL backend
  # services.postgresql = {
  #   enable = true;
  #   package = pkgs.postgresql_16;
  #   enableTCPIP = true;
  # };

  # Backup kanidm database
  services.restic.backups.kanidm = {
    initialize = true;
    paths = [ "/var/lib/kanidm" ];
    repository = "/var/backups/kanidm";
    passwordFile = "/etc/nixos/secrets/restic-password";
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
