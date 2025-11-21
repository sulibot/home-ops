# VolSync Configuration Audit

Generated: 2025-11-21

## Summary

- **Total apps with config PVCs**: 23
- **Apps with VolSync enabled**: 18 (78%)
- **Apps needing VolSync**: 5 (22%)

## Apps with VolSync ✓

These apps are already configured with VolSync backup and restore:

| App | Namespace | Status |
|-----|-----------|--------|
| autobrr | default | ✓ Configured |
| emby | default | ✓ Configured |
| filebrowser | default | ✓ Configured |
| immich | default | ✓ Configured |
| jellyseerr | default | ✓ Configured |
| lidarr | default | ✓ Configured |
| nzbget | default | ✓ Configured |
| overseerr | default | ✓ Configured |
| plex | default | ✓ Configured |
| prowlarr | default | ✓ Configured |
| qbittorrent | default | ✓ Configured |
| qui | default | ✓ Configured |
| radarr | default | ✓ Configured |
| sabnzbd | default | ✓ Configured |
| slskd | default | ✓ Configured |
| sonarr | default | ✓ Configured |
| tautulli | default | ✓ Configured |
| thelounge | default | ✓ Configured |

## Apps Missing VolSync Configuration ✗

These apps have config PVCs but are NOT backed up:

### 1. atuin
- **Location**: `kubernetes/apps/default/atuin/`
- **HelmRelease**: `kubernetes/apps/default/atuin/app/helmrelease.yaml`
- **Kustomization**: `kubernetes/apps/default/atuin/ks.yaml`
- **Priority**: Medium
- **Notes**: Shell history sync server

### 2. cross-seed
- **Location**: `kubernetes/apps/default/cross-seed/`
- **HelmRelease**: `kubernetes/apps/default/cross-seed/app/helmrelease.yaml`
- **Kustomization**: `kubernetes/apps/default/cross-seed/ks.yaml`
- **Priority**: Low
- **Notes**: Torrent cross-seeding automation, config is regenerable

### 3. home-assistant
- **Location**: `kubernetes/apps/default/home-assistant/`
- **HelmRelease**: `kubernetes/apps/default/home-assistant/app/helmrelease.yaml`
- **Kustomization**: `kubernetes/apps/default/home-assistant/ks.yaml`
- **Priority**: **HIGH**
- **Notes**: Smart home automation hub with automations, device configs, historical data

### 4. mosquitto
- **Location**: `kubernetes/apps/default/mosquitto/`
- **HelmRelease**: `kubernetes/apps/default/mosquitto/app/helmrelease.yaml`
- **Kustomization**: `kubernetes/apps/default/mosquitto/ks.yaml`
- **Priority**: Low-Medium
- **Notes**: MQTT broker, config includes user credentials and ACLs

### 5. tqm
- **Location**: `kubernetes/apps/default/tqm/`
- **HelmRelease**: `kubernetes/apps/default/tqm/app/helmrelease.yaml`
- **Kustomization**: `kubernetes/apps/default/tqm/ks.yaml`
- **Priority**: Medium
- **Notes**: Unknown app, review if important

## Recommended Actions

### High Priority (Do First)

1. **home-assistant** - Contains critical smart home configuration
   - Automations
   - Device integrations
   - User settings
   - Historical sensor data
   - Loss would require complete reconfiguration

### Medium Priority

2. **atuin** - Shell history database
   - Losing this would lose command history
   - Not critical but valuable

3. **mosquitto** - MQTT broker config
   - User credentials
   - ACL rules
   - Broker settings
   - Can be regenerated but annoying

4. **tqm** - Needs review
   - Determine if important
   - If so, add to VolSync

### Low Priority

5. **cross-seed** - Config is simple
   - Minimal configuration
   - Easy to regenerate
   - Can be added for completeness

## How to Add VolSync to an App

For each app missing VolSync, follow these steps:

### 1. Update the app's Kustomization file

Edit `kubernetes/apps/default/<app>/ks.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app>
  namespace: flux-system
spec:
  # Add this section:
  components:
    - ../../../../components/volsync

  # Add these dependencies:
  dependsOn:
    - name: ceph-csi
      namespace: flux-system
    - name: volsync
      namespace: flux-system

  # Add these substitutions:
  postBuild:
    substitute:
      APP: <app>
      VOLSYNC_CAPACITY: 10Gi                          # Adjust size as needed
      VOLSYNC_STORAGECLASS: csi-cephfs-config-sc
      VOLSYNC_CACHE_SNAPSHOTCLASS: csi-cephfs-config-sc
      VOLSYNC_SNAPSHOTCLASS: csi-cephfs-config-snapclass
```

### 2. Verify the app uses existingClaim

Check `kubernetes/apps/default/<app>/app/helmrelease.yaml`:

```yaml
persistence:
  config:
    enabled: true
    existingClaim: "<app>-config"  # Must match ${APP}-config pattern
```

### 3. Commit and apply

```bash
git add kubernetes/apps/default/<app>/ks.yaml
git commit -m "feat: Enable VolSync backup for <app>"
git push

flux reconcile source git flux-system -n flux-system
flux reconcile kustomization <app> -n flux-system
```

### 4. Verify backup is working

```bash
# Check ReplicationSource was created
kubectl get replicationsource <app>-src -n default

# Check ReplicationDestination was created
kubectl get replicationdestination <app>-dst -n default

# Wait for first backup (runs hourly)
kubectl get replicationsource <app>-src -n default -w

# Check backup status
kubectl describe replicationsource <app>-src -n default
```

## Example: Adding VolSync to home-assistant

### Before
```yaml
# kubernetes/apps/default/home-assistant/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: home-assistant
  namespace: flux-system
spec:
  interval: 30m
  path: ./kubernetes/manifests/apps/default/home-assistant/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: default
```

### After
```yaml
# kubernetes/apps/default/home-assistant/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: home-assistant
  namespace: flux-system
spec:
  components:
    - ../../../../components/volsync

  dependsOn:
    - name: ceph-csi
      namespace: flux-system
    - name: volsync
      namespace: flux-system

  interval: 30m
  path: ./kubernetes/manifests/apps/default/home-assistant/app
  postBuild:
    substitute:
      APP: home-assistant
      VOLSYNC_CAPACITY: 25Gi  # Home Assistant can grow large with history
      VOLSYNC_STORAGECLASS: csi-cephfs-config-sc
      VOLSYNC_CACHE_SNAPSHOTCLASS: csi-cephfs-config-sc
      VOLSYNC_SNAPSHOTCLASS: csi-cephfs-config-snapclass
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  targetNamespace: default
```

## Storage Size Recommendations

Based on typical app data sizes:

| App | Recommended Size | Notes |
|-----|------------------|-------|
| home-assistant | 25-50Gi | Large history database, many integrations |
| atuin | 5Gi | Shell history, grows slowly |
| mosquitto | 1Gi | Minimal config, mostly text |
| cross-seed | 2Gi | Simple config files |
| tqm | 5Gi | Unknown, start conservative |

## Verification Checklist

After adding VolSync to an app:

- [ ] ReplicationSource created and showing status
- [ ] ReplicationDestination created
- [ ] ExternalSecret created for Kopia credentials
- [ ] First backup completed successfully (check lastSyncTime)
- [ ] PVC labels show `kustomize.toolkit.fluxcd.io/name: <app>`
- [ ] Kopia repository shows snapshots for the app

```bash
# Quick verification script
APP=home-assistant

echo "Checking VolSync resources for $APP..."
kubectl get replicationsource ${APP}-src -n default
kubectl get replicationdestination ${APP}-dst -n default
kubectl get externalsecret ${APP}-volsync-secret -n default
kubectl get pvc ${APP}-config -n default

echo "\nChecking backup status..."
kubectl get replicationsource ${APP}-src -n default -o jsonpath='{.status.lastSyncTime}{"\n"}'
```

## Related Documentation

- [VolSync + Kopia System Overview](VOLSYNC_KOPIA_BACKUP_SYSTEM.md)
- VolSync Component: `kubernetes/components/volsync/`
- MutatingAdmissionPolicy: `docs/volsync-kopia-mutatingadmissionpolicy.yaml`
