# VolSync Kopia Repository Access

## Overview

All namespaces use one shared Kopia repository on MinIO S3:
- Repository: `s3://cnpg-backups/volsync-kopia`
- Endpoint: `https://s3.sulibot.com`

Repository credentials are delivered per-namespace via ExternalSecrets (`${APP}-volsync-secret`).

## Architecture

```
MinIO S3 (cnpg-backups/volsync-kopia)
  -> ExternalSecret (${APP}-volsync)
  -> Secret (${APP}-volsync-secret)
  -> VolSync mover Job (Kopia S3)
```

## Required Secret Keys

Each `${APP}-volsync-secret` must include:
- `KOPIA_REPOSITORY`
- `KOPIA_S3_ENDPOINT`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION`
- `AWS_REGION`
- `AWS_S3_ENDPOINT`
- `KOPIA_PASSWORD`

## Restore Dependency Order (GitOps)

1. `ceph-csi` and `volsync` controllers Ready
2. ExternalSecret synced and `${APP}-volsync-secret` present
3. App Kustomization with VolSync component reconciles

## New Namespace Enablement

To enable backups for a new app namespace:
1. Add `${APP}-volsync` ExternalSecret for that namespace.
2. Ensure namespace has the app PVC(s) to back up.
3. Include `kubernetes/components/volsync` in the app Kustomization.
4. Verify `ReplicationSource` shows latest mover result `Successful`.

## Troubleshooting

- `signature does not match`: check `${APP}-volsync-secret` keys and MinIO user policy scope.
- `can't connect to storage`: validate `KOPIA_REPOSITORY` and `KOPIA_S3_ENDPOINT`.
- Stale failed mover pods: clean failed Jobs/Pods after fixing root cause, then trigger sync.
