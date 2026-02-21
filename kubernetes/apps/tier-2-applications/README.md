# Tier 2: Applications

**Bootstrap Phase**: Parallel (wait: false)
**Purpose**: End-user applications and workloads.

## Apps in this Tier

### Media Services
- **plex**: Media server
- **plex-tools**: Plex maintenance tools
- **emby**: Alternative media server
- **jellyseerr**: Media request management
- **overseerr**: Media request management (alt)
- **tautulli**: Plex analytics

### Home Automation
- **home-assistant**: Home automation platform
- **mosquitto**: MQTT broker
- **zigbee**: Zigbee2MQTT
- **zwave**: Z-Wave JS UI
- **go2rtc**: Real-time communication

### Media Acquisition
- **radarr**: Movie management
- **radarr-4k**: 4K movie management
- **sonarr**: TV show management
- **sonarr-4k**: 4K TV show management
- **lidarr**: Music management
- **prowlarr**: Indexer manager
- **autobrr**: Torrent automation
- **cross-seed**: Cross-seeding automation
- **qbittorrent**: Torrent client
- **nzbget**: Usenet client
- **sabnzbd**: Usenet client (alt)
- **slskd**: Soulseek client

### Productivity
- **actual**: Budget management
- **paperless**: Document management
- **immich**: Photo management
- **bookshelf**: Audiobook server
- **filebrowser**: File browser
- **thelounge**: IRC client

### Development
- **actions-runner-controller**: GitHub Actions runners
- **atuin**: Shell history sync
- **karakeep**: Karaoke management

### Other Services
- **smtp-relay**: Email relay
- **notifier**: Notification service
- **recyclarr**: *arr app configuration
- **tqm**: Task queue manager
- **tuppr**: Service (TBD)
- **fusion**: Service (TBD)
- **qui**: Service (TBD)
- **seerr**: Service (TBD)
- **lazylibrarian**: Book management
- **gatus**: Status page
- **echo**: Network testing

## Bootstrap Behavior

- **Interval**: 2m (aggressive during bootstrap) → 15m (steady-state)
- **Wait**: `false` - Deploy in parallel, retry until dependencies ready
- **Dependencies**: Implicit via Kubernetes (PVC binding, secret injection)
- **Retries**: Apps retry automatically if secrets/storage not ready yet

## Why These Apps?

These are the actual workloads users interact with. They depend on:
- Tier 0: Networking (Cilium), Secrets (external-secrets), Storage (ceph-csi)
- Tier 1: Certificates, Databases, Backup/restore

They can start deploying immediately and will wait (via failed health checks and retries) until their dependencies are ready.

## Critical Apps Tracking

The bootstrap detection script specifically waits for these to be Ready:
- **plex**: Primary media server
- **home-assistant**: Home automation hub
- **immich**: Photo management (complex, multiple dependencies)

Once these 3 are Ready, bootstrap is considered complete and intervals switch to steady-state.
