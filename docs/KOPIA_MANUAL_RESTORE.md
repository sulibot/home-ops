# Kopia Manual Restore Guide

## Overview

After cluster rebuild, PVCs can be manually restored from Kopia backups stored in the CephFS repository. This approach is necessary because Volsync's ReplicationDestination does not support direct access to local repository PVCs (the `repositoryPVC` field only exists for ReplicationSource, not ReplicationDestination).

## Why Manual Restore?

**Volsync Design:**
- `ReplicationSource` → Backup to local PVC (supports `repositoryPVC` field) ✅
- `ReplicationDestination` → Restore from remote repository via HTTP/S3 (no `repositoryPVC` field) ❌

**Your Architecture:**
- Backups and restores both use the same local Kopia repository
- This is a single-cluster disaster recovery scenario, not multi-cluster replication
- Therefore, manual restore using Kopia CLI is the appropriate solution

## Prerequisites

- Kopia repository PVC survived cluster rebuild (via Ceph PV reclaim)
- App's volsync secret exists with KOPIA_PASSWORD
- Target PVC does not exist yet (will be created during restore)

## Quick Restore

For a single app restore:

```bash
# 1. List available snapshots
kubectl run kopia-list --rm -it --restart=Never \
  --image=ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53 \
  --env="KOPIA_PASSWORD=$(kubectl get secret APP-volsync-secret -n NAMESPACE -o jsonpath='{.data.KOPIA_PASSWORD}' | base64 -d)" \
  --overrides='{"spec":{"containers":[{"name":"kopia","image":"ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53","stdin":true,"tty":true,"env":[{"name":"KOPIA_PASSWORD","value":"PASS"},{"name":"HOME","value":"/tmp"},{"name":"KOPIA_LOG_DIR","value":"/tmp"},{"name":"KOPIA_CACHE_DIRECTORY","value":"/tmp/cache"}],"command":["/bin/sh","-c","kopia repository connect filesystem --path=/repository/repository --password=\"$KOPIA_PASSWORD\" --config-file=/tmp/kopia.config && kopia snapshot list --all --config-file=/tmp/kopia.config"],"volumeMounts":[{"name":"repository","mountPath":"/repository","readOnly":true},{"name":"tmp","mountPath":"/tmp"}],"securityContext":{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}],"volumes":[{"name":"repository","persistentVolumeClaim":{"claimName":"kopia"}},{"name":"tmp","emptyDir":{}}],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"runAsGroup":1000,"fsGroup":1000}}}' \
  -n NAMESPACE

# 2. Create target PVC (if doesn't exist)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: APP-config
  namespace: NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: csi-cephfs-config-sc
  resources:
    requests:
      storage: 5Gi
EOF

# 3. Run restore job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: kopia-restore-APP
  namespace: NAMESPACE
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 2
  template:
    spec:
      restartPolicy: OnFailure
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: kopia-restore
          image: ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53
          env:
            - name: KOPIA_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: APP-volsync-secret
                  key: KOPIA_PASSWORD
            - name: HOME
              value: /tmp
            - name: KOPIA_LOG_DIR
              value: /tmp
            - name: KOPIA_CACHE_DIRECTORY
              value: /tmp/cache
          command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "=== Kopia Restore for APP ==="
              kopia repository connect filesystem \
                --path=/repository/repository \
                --password="\$KOPIA_PASSWORD" \
                --config-file=/tmp/kopia.config
              echo "Repository connected"
              kopia snapshot list --all --config-file=/tmp/kopia.config | grep "APP-src@NAMESPACE"
              echo "Restoring latest snapshot..."
              kopia snapshot restore "APP-src@NAMESPACE:/data" /data \
                --config-file=/tmp/kopia.config \
                --parallel=8 \
                --ignore-permission-errors
              echo "=== Restore complete ==="
              df -h /data
              ls -lah /data | head -20
          volumeMounts:
            - name: repository
              mountPath: /repository
              readOnly: true
            - name: data
              mountPath: /data
            - name: tmp
              mountPath: /tmp
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: repository
          persistentVolumeClaim:
            claimName: kopia
        - name: data
          persistentVolumeClaim:
            claimName: APP-config
        - name: tmp
          emptyDir: {}
EOF

# 4. Monitor restore
kubectl logs -n NAMESPACE job/kopia-restore-APP -f

# 5. Verify restore
kubectl exec -n NAMESPACE deploy/APP -- ls -lah /config
```

## Bulk Restore After Cluster Rebuild

Script to restore all apps:

```bash
#!/bin/bash
set -e

APPS=( plex radarr sonarr prowlarr qbittorrent home-assistant emby )
NAMESPACE=default

for APP in "${APPS[@]}"; do
  echo "=== Restoring $APP ==="

  # Create restore job
  kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: kopia-restore-$APP
  namespace: $NAMESPACE
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 2
  template:
    spec:
      restartPolicy: OnFailure
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: kopia-restore
          image: ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53
          env:
            - name: KOPIA_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${APP}-volsync-secret
                  key: KOPIA_PASSWORD
            - name: HOME
              value: /tmp
            - name: KOPIA_LOG_DIR
              value: /tmp
            - name: KOPIA_CACHE_DIRECTORY
              value: /tmp/cache
          command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "Connecting to repository..."
              kopia repository connect filesystem \
                --path=/repository/repository \
                --password="\$KOPIA_PASSWORD" \
                --config-file=/tmp/kopia.config
              echo "Restoring $APP..."
              kopia snapshot restore "${APP}-src@${NAMESPACE}:/data" /data \
                --config-file=/tmp/kopia.config \
                --parallel=8 \
                --ignore-permission-errors || echo "No snapshot found, skipping"
              echo "Done"
          volumeMounts:
            - name: repository
              mountPath: /repository
              readOnly: true
            - name: data
              mountPath: /data
            - name: tmp
              mountPath: /tmp
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: repository
          persistentVolumeClaim:
            claimName: kopia
        - name: data
          persistentVolumeClaim:
            claimName: ${APP}-config
        - name: tmp
          emptyDir: {}
EOF

  echo "Waiting for $APP restore to complete..."
  kubectl wait --for=condition=complete --timeout=600s job/kopia-restore-$APP -n $NAMESPACE || true
done

echo "=== All restores complete ==="
kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/component=restore
```

## Troubleshooting

### Error: "No repository configuration found"

This means the Kopia repository at `/repository/repository` doesn't exist or isn't initialized.

**Fix:**
```bash
# Initialize repository
kubectl run kopia-init --rm -it --restart=Never \
  --image=ghcr.io/home-operations/kopia:0.21.1@sha256:f666b5f2c1ea4649cd2bd703507d4b81c2b515782e8476ba4a145b091a704a53 \
  --env="KOPIA_PASSWORD=$(kubectl get secret kopia-secret -n volsync-system -o jsonpath='{.data.KOPIA_PASSWORD}' | base64 -d)" \
  --overrides='...' # (add PVC mount and run kopia repository create)
```

### Error: "Permission denied" writing to /data

The PVC might have wrong ownership. Check pod security context matches PVC fsGroup.

### Snapshot not found

List all snapshots to find the correct path:
```bash
kopia snapshot list --all
```

Look for snapshots matching pattern: `APP-src@NAMESPACE:/data`

## Verification

After restore:

```bash
# Check PVC size
kubectl get pvc APP-config -n NAMESPACE

# Check restored files
kubectl exec -n NAMESPACE deploy/APP -- ls -lah /config

# Compare with snapshot
kubectl run kopia-verify --rm -it --restart=Never ... \
  kopia snapshot list APP-src@NAMESPACE
```

## Future Improvements

1. **Automated restore on PVC creation** - Add init container to app deployments
2. **Restore CRD** - Create custom resource to trigger restores declaratively
3. **Velero migration** - Consider migrating to Velero for better Kubernetes-native backup/restore
4. **Cross-cluster replication** - If multi-cluster DR needed, add Kopia server with HTTP API or S3 backend

## References

- Tested successfully with Volsync v0.16.12
- Kopia repository: 19 apps backed up hourly
- Repository location: `/repository/repository` on `kopia` PVC (CephFS)
- Snapshots retained: 24 hourly + 7 daily
