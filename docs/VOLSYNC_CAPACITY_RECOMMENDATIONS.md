# VolSync Capacity Recommendations

## Current Configuration Analysis

### Media Servers & Libraries

| App | Current | Recommended | Change | Rationale |
|-----|---------|-------------|--------|-----------|
| **plex** | 50Gi | 50Gi | ✓ Keep | Large metadata library, watch history, thumbnails, transcoding settings. Good size. |
| **emby** | 10Gi | 15Gi | ↑ +5Gi | Similar to Plex but smaller library. Room for growth. |
| **immich** | 10Gi | 15Gi | ↑ +5Gi | Photo library metadata, thumbnails, ML models, facial recognition data. Grows with photo count. |
| **tautulli** | 5Gi | 10Gi | ↑ +5Gi | Extensive watch history database, statistics, graphs. Grows continuously. |

### Media Management (*arr stack)

| App | Current | Recommended | Change | Rationale |
|-----|---------|-------------|--------|-----------|
| **sonarr** | 5Gi | 10Gi | ↑ +5Gi | TV show database with episode history, artwork, custom formats. Larger libraries need more space. |
| **radarr** | 5Gi | 10Gi | ↑ +5Gi | Movie database with metadata, custom formats, quality profiles. Similar to Sonarr. |
| **lidarr** | 10Gi | 10Gi | ✓ Keep | Music database can be extensive. Good size. |
| **prowlarr** | 1Gi | 3Gi | ↑ +2Gi | Indexer configs, search history, stats. Minimal but 1Gi is tight. |

### Download Clients

| App | Current | Recommended | Change | Rationale |
|-----|---------|-------------|--------|-----------|
| **qbittorrent** | 2Gi | 5Gi | ↑ +3Gi | Torrent session state, resume data, fastresume files. Large torrent counts need more. |
| **sabnzbd** | 10Gi | 5Gi | ↓ -5Gi | NZB history and queue state. 10Gi is excessive for this. |
| **nzbget** | 2Gi | 3Gi | ↑ +1Gi | Similar to sabnzbd but lighter. Small increase for safety. |

### Request Management

| App | Current | Recommended | Change | Rationale |
|-----|---------|-------------|--------|-----------|
| **overseerr** | 10Gi | 5Gi | ↓ -5Gi | Request database, user data, notifications. 10Gi is overkill. |
| **jellyseerr** | 5Gi | 5Gi | ✓ Keep | Same as Overseerr. 5Gi is appropriate. |

### Download Automation

| App | Current | Recommended | Change | Rationale |
|-----|---------|-------------|--------|-----------|
| **autobrr** | 1Gi | 2Gi | ↑ +1Gi | Release filters, IRC logs, announce history. Minimal but room for growth. |
| **cross-seed** | 5Gi | 3Gi | ↓ -2Gi | Simple config and torrent cache. 5Gi is more than needed. |

### Utilities & Tools

| App | Current | Recommended | Change | Rationale |
|-----|---------|-------------|--------|-----------|
| **filebrowser** | 10Gi | 5Gi | ↓ -5Gi | User settings, file previews cache. 10Gi is excessive. |
| **qui** | 1Gi | 2Gi | ↑ +1Gi | qBittorrent UI settings and cache. Small increase for safety. |
| **thelounge** | 1Gi | 3Gi | ↑ +2Gi | IRC chat logs, can grow significantly over time. |
| **slskd** | 5Gi | 5Gi | ✓ Keep | Soulseek config, search cache, user data. Good size. |

### Smart Home & Services

| App | Current | Recommended | Change | Rationale |
|-----|---------|-------------|--------|-----------|
| **home-assistant** | 25Gi | 25Gi | ✓ Keep | Large historical database, integrations, automations. Critical app. |
| **mosquitto** | 5Gi | 2Gi | ↓ -3Gi | MQTT broker config and persistence. Very minimal. |
| **atuin** | 5Gi | 5Gi | ✓ Keep | Shell history database. Good headroom for growth. |

## Summary of Changes

### Increases Needed (10 apps)
- emby: 10Gi → 15Gi (+5Gi)
- immich: 10Gi → 15Gi (+5Gi)
- tautulli: 5Gi → 10Gi (+5Gi)
- sonarr: 5Gi → 10Gi (+5Gi)
- radarr: 5Gi → 10Gi (+5Gi)
- prowlarr: 1Gi → 3Gi (+2Gi)
- qbittorrent: 2Gi → 5Gi (+3Gi)
- nzbget: 2Gi → 3Gi (+1Gi)
- autobrr: 1Gi → 2Gi (+1Gi)
- qui: 1Gi → 2Gi (+1Gi)
- thelounge: 1Gi → 3Gi (+2Gi)

### Decreases Recommended (4 apps)
- sabnzbd: 10Gi → 5Gi (-5Gi)
- overseerr: 10Gi → 5Gi (-5Gi)
- cross-seed: 5Gi → 3Gi (-2Gi)
- filebrowser: 10Gi → 5Gi (-5Gi)
- mosquitto: 5Gi → 2Gi (-3Gi)

### Keep As-Is (7 apps)
- plex: 50Gi
- lidarr: 10Gi
- jellyseerr: 5Gi
- slskd: 5Gi
- home-assistant: 25Gi
- atuin: 5Gi

## Rationale by Category

### Why Media Servers Need More Space

**Plex/Emby/Immich**: These apps store:
- Metadata for every media item
- Thumbnails and artwork (can be GBs)
- Watch history and user preferences
- Transcoding profiles and settings
- For Immich: ML models, facial recognition data, duplicate detection cache

**Tautulli**: Stores every play session, statistics, graphs over years. This grows continuously and never shrinks.

### Why *arr Apps Need Consistent Space

**Sonarr/Radarr/Lidarr**: Each stores:
- Full media library metadata
- Quality profiles and custom formats
- Download history and statistics
- Import history
- Artwork cache
- Grow with library size

**Prowlarr**: Lighter than the others but stores indexer configs, search history, and statistics. 1Gi is too tight.

### Why Download Clients Vary

**qBittorrent**: With hundreds of torrents, fastresume data and session state can grow large. 2Gi is risky.

**Sabnzbd/NZBGet**: Only store queue state and history. Much lighter than torrent clients. 10Gi is overkill.

### Why Some Apps Are Oversized

**Overseerr/Filebrowser**: Simple web UIs with minimal databases. 10Gi is 5-10x what they'll ever use.

**Cross-seed**: Just config files and torrent cache. 5Gi is generous, 3Gi is plenty.

**Mosquitto**: MQTT messages are ephemeral. Persistence is minimal. 2Gi is more than enough.

## Storage Impact

**Total Current**: 202Gi
**Total Recommended**: 201Gi
**Net Change**: -1Gi

The recommendations balance storage more appropriately across apps without increasing total usage.

## Implementation Priority

### High Priority (Do First)
These apps are most likely to hit capacity issues:

1. **qbittorrent** (2Gi → 5Gi) - Most likely to run out
2. **sonarr** (5Gi → 10Gi) - Large TV libraries
3. **radarr** (5Gi → 10Gi) - Large movie libraries
4. **tautulli** (5Gi → 10Gi) - Continuous growth
5. **immich** (10Gi → 15Gi) - Photo libraries grow fast

### Medium Priority
These should be adjusted but less urgent:

6. **emby** (10Gi → 15Gi)
7. **prowlarr** (1Gi → 3Gi)
8. **thelounge** (1Gi → 3Gi)

### Low Priority (Optional)
These are optimizations but not urgent:

9. **sabnzbd** (10Gi → 5Gi) - Reduce waste
10. **overseerr** (10Gi → 5Gi) - Reduce waste
11. **filebrowser** (10Gi → 5Gi) - Reduce waste
12. **cross-seed** (5Gi → 3Gi) - Reduce waste
13. **mosquitto** (5Gi → 2Gi) - Reduce waste
14. **autobrr** (1Gi → 2Gi)
15. **qui** (1Gi → 2Gi)
16. **nzbget** (2Gi → 3Gi)

## Notes on PVC Resizing

### CephFS Supports Online Expansion
Your storage class `csi-cephfs-config-sc` supports volume expansion, so you can:
- Increase sizes without downtime
- Changes take effect immediately
- No need to recreate PVCs

### Decreasing Size Requires Recreation
To reduce PVC sizes:
1. Backup data with VolSync (already running)
2. Delete the app (kubectl delete kustomization <app>)
3. Delete the PVC (kubectl delete pvc <app>-config)
4. Update ks.yaml with new VOLSYNC_CAPACITY
5. Redeploy app (flux reconcile kustomization <app>)
6. ReplicationDestination will restore from backup

## Verification After Changes

Check PVC sizes:
```bash
kubectl get pvc -n default -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,USED:.status.capacity.storage
```

Monitor for capacity issues:
```bash
# Check actual usage
kubectl exec -n default <pod> -- df -h /config
```
