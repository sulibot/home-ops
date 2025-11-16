# 1Password Items Reference

This document lists all the 1Password items that need to exist in your `Kubernetes` vault (vault ID: 1) for the ExternalSecrets to work.

## Required 1Password Items

### 1. actions-runner
**Used by:** Actions Runner Controller

```yaml
ACTIONS_RUNNER_APP_ID: "123456"
ACTIONS_RUNNER_INSTALLATION_ID: "78901234"
ACTIONS_RUNNER_PRIVATE_KEY: |
  -----BEGIN RSA PRIVATE KEY-----
  <your-private-key-here>
  -----END RSA PRIVATE KEY-----
```

### 2. alertmanager
**Used by:** Kube Prometheus Stack Alertmanager

```yaml
ALERTMANAGER_PUSHOVER_TOKEN: "your-pushover-app-token"
```

### 3. autobrr
**Used by:** Autobrr

```yaml
AUTOBRR_SESSION_SECRET: "random-secret-string-here"
```

### 4. cloudflare
**Used by:** Cloudflare DNS, Cloudflare Tunnel

```yaml
CLOUDFLARE_DNS_TOKEN: "your-cloudflare-dns-api-token"
CLOUDFLARE_ZONE_ID: "your-zone-id"
CLOUDFLARE_ACCOUNT_TAG: "your-account-id"
CLOUDFLARE_TUNNEL_ID: "your-tunnel-id"
CLOUDFLARE_TUNNEL_SECRET: "your-tunnel-secret"
```

### 5. cross-seed
**Used by:** Cross-seed

```yaml
CROSS_SEED_API_KEY: "your-cross-seed-api-key"
CROSS_SEED_PORT: "2468"
```

### 6. flux
**Used by:** Flux GitHub Status Token

```yaml
FLUX_GITHUB_TOKEN: "ghp_yourGitHubPersonalAccessToken"
```

### 7. gatus
**Used by:** Gatus, Alertmanager

```yaml
BUDDY_DDNS_HOSTNAME: "ddns.example.com"
BUDDY_HEARTBEAT_TOKEN: "your-heartbeat-token"
BUDDY_PUSHOVER_TOKEN: "your-pushover-token"
BUDDY_PUSHOVER_USER_KEY: "your-pushover-user-key"
BUDDY_STATUS_HOSTNAME: "status.example.com"
```

### 8. grafana
**Used by:** Grafana

```yaml
GF_SECURITY_ADMIN_PASSWORD: "your-admin-password"
```

### 9. home-assistant
**Used by:** Home Assistant

```yaml
HASS_DARKSKY_API_KEY: "your-darksky-api-key"
HASS_ECOBEE_API_KEY: "your-ecobee-api-key"
HASS_ELEVATION: "100"
HASS_GOOGLE_PROJECT_ID: "your-google-project-id"
HASS_GOOGLE_SECURE_DEVICES_PIN: "1234"
HASS_LATITUDE: "40.7128"
HASS_LONGITUDE: "-74.0060"
HASS_PIRATE_WEATHER_API_KEY: "your-pirate-weather-api-key"
```

### 10. jellyseerr
**Used by:** Jellyseerr, Notifier

```yaml
JELLYSEERR_API_KEY: "your-jellyseerr-api-key"
JELLYSEERR_PUSHOVER_TOKEN: "your-pushover-token"
```

### 11. plex
**Used by:** Plex Off-Deck Tool

```yaml
PLEX_TOKEN: "your-plex-token"
```

### 12. prowlarr
**Used by:** Prowlarr, Cross-seed

```yaml
PROWLARR_API_KEY: "your-prowlarr-api-key"
```

### 13. pushover
**Used by:** Notifier, Alertmanager

```yaml
PUSHOVER_USER_KEY: "your-pushover-user-key"
```

### 14. qui
**Used by:** qBittorrent UI, Cross-seed

```yaml
QUI_SESSION_SECRET: "random-session-secret"
QUI_CLIENT_API_KEY: "your-qui-api-key"
```

### 15. radarr
**Used by:** Radarr, Recyclarr, Cross-seed, Notifier

```yaml
RADARR_API_KEY: "your-radarr-api-key"
RADARR_PUSHOVER_TOKEN: "your-pushover-token"
```

### 16. slskd
**Used by:** Soulseek Daemon

```yaml
SLSKD_SLSK_USERNAME: "your-soulseek-username"
SLSKD_SLSK_PASSWORD: "your-soulseek-password"
```

### 17. smtp-relay
**Used by:** SMTP Relay

```yaml
SMTP_RELAY_HOSTNAME: "smtp.example.com"
SMTP_RELAY_PASSWORD: "your-smtp-password"
SMTP_RELAY_SERVER: "smtp.gmail.com:587"
SMTP_RELAY_USERNAME: "your-email@gmail.com"
```

### 18. sonarr
**Used by:** Sonarr, Recyclarr, Cross-seed, Notifier

```yaml
SONARR_API_KEY: "your-sonarr-api-key"
SONARR_PUSHOVER_TOKEN: "your-pushover-token"
```

### 19. tautulli
**Used by:** Tautulli

```yaml
TAUTULLI_API_KEY: "your-tautulli-api-key"
```

### 20. turbo-ac-tls
**Used by:** Certificate Import/Export

This item should contain TLS certificate data:
```yaml
# Store as a "Document" type in 1Password with base64-encoded content
# The ExternalSecret will decode it automatically
tls.crt: "<base64-encoded-certificate>"
tls.key: "<base64-encoded-private-key>"
```

### 21. unifi
**Used by:** Unpoller

```yaml
UNIFI_API_KEY: "your-unifi-api-key"
```

### 22. volsync-template
**Used by:** VolSync (all apps), Kopia

```yaml
KOPIA_PASSWORD: "your-kopia-repository-password"
KOPIA_FS_PATH: "/repository"
KOPIA_REPOSITORY: "filesystem:///repository"
```

### 23. zigbee
**Used by:** Zigbee2MQTT

```yaml
ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID: "[0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77]"
ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID: "0x1234"
ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY: "[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]"
```

## How to Create These Items in 1Password

1. Log into 1Password
2. Navigate to your `Kubernetes` vault
3. For each item above:
   - Click "New Item"
   - Choose "Password" or "Secure Note" type
   - Set the title to match the key name (e.g., "flux", "cloudflare", etc.)
   - Add custom fields for each value listed
   - Save the item

## Bootstrap Secret

The bootstrap secret [secret.sops.yaml](./onepassword/app/secret.sops.yaml) contains:
- `1password-credentials.json`: 1Password Connect credentials file
- `token`: 1Password Connect API token

This secret is encrypted with SOPS and is required for the 1Password Connect server to authenticate with your 1Password account.

## Notes

- All values above are placeholders and should be replaced with your actual credentials
- API keys can typically be generated from the respective application's settings page
- For session secrets, use a cryptographically secure random string generator
- The `turbo-ac-tls` certificate should be base64-encoded PEM format
- Zigbee network keys should be random hex arrays
