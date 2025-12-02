#!/usr/bin/env bash
set -euo pipefail

echo "=== Reconciling all app kustomizations ==="
echo ""

for app in atuin autobrr emby filebrowser home-assistant immich jellyseerr lidarr mosquitto nzbget overseerr plex prowlarr qbittorrent qui radarr redis sabnzbd slskd tautulli thelounge; do
  echo "Reconciling: $app"
  flux reconcile ks "$app" --with-source 2>&1 | grep -E "(annotating|revision|error)" || echo "  (reconciled)"
done

echo ""
echo "=== All apps reconciled ==="
