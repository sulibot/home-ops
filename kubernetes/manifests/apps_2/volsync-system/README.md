# Volsync Configuration

Volsync provides backup and restore capabilities for PVCs using Kopia.

## Prerequisites

### 1. VolumeSnapshotClass
A VolumeSnapshotClass must be configured for your CSI driver. This is already set up in the ceph-csi configuration.

### 2. 1Password Secret Setup

Create a secret in 1Password named `volsync-template` in the `Kubernetes` vault with the following field:

- **Field name**: `KOPIA_PASSWORD`
- **Field type**: Password
- **Value**: Generate a strong random password (this encrypts your backup repository)

This password will be used by Kopia to encrypt all backup data.

## How it Works

1. Each application that uses volsync will have an ExternalSecret created that references the `volsync-template` in 1Password
2. The ExternalSecret creates a secret named `<app>-volsync-secret` containing:
   - `KOPIA_PASSWORD`: The encryption password for the Kopia repository
   - `KOPIA_REPOSITORY`: The repository location (filesystem:///repository)
   - `KOPIA_FS_PATH`: The filesystem path (/repository)

3. Volsync uses these secrets to:
   - **ReplicationSource**: Back up PVCs to the Kopia repository
   - **ReplicationDestination**: Restore PVCs from the Kopia repository

## Repository Storage

Currently configured to use local filesystem storage at `/repository`. This requires:
- A persistent volume mounted at `/repository` in the volsync mover pods
- Sufficient storage capacity for all backups

**TODO**: Configure NFS or S3 storage for the Kopia repository for better durability.

## Usage

To enable volsync for an application, include the volsync component in your kustomization:

```yaml
components:
  - ../../../../components/volsync
```

And set the APP variable:

```yaml
patches:
  - patch: |-
      - op: replace
        path: /metadata/name
        value: <app-name>
    target:
      kind: PersistentVolumeClaim
```

The volsync component will automatically create:
- ExternalSecret for Kopia credentials
- ReplicationSource for backups
- ReplicationDestination for restores
