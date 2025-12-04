# Cross-Namespace Kopia Repository Access

## Overview

All namespaces share a single centralized Kopia backup repository stored in the `volsync-system` namespace. This is achieved using CephFS's ReadWriteMany (RWX) capability, where multiple PVCs in different namespaces bind to static PVs that reference the same underlying CephFS subvolume.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ CephFS Backups Subvolume (RWX)                          │
│ volumeHandle: 0001-0024-...-841e604c-1dd5-4a09-...     │
└───────────┬──────────────────────────────┬──────────────┘
            │                              │
    ┌───────▼──────────┐          ┌────────▼───────────┐
    │ PV: kopia-repo-  │          │ PV: kopia-repo-    │
    │     pv-volsync-  │          │     pv-default     │
    │     system       │          │                    │
    └───────┬──────────┘          └────────┬───────────┘
            │                              │
    ┌───────▼──────────┐          ┌────────▼───────────┐
    │ PVC: kopia       │          │ PVC: kopia         │
    │ NS: volsync-     │          │ NS: default        │
    │     system       │          │                    │
    └──────────────────┘          └────────────────────┘
```

## Repository Path Convention

- **Mount point**: `/repository` (where the PVC is mounted in containers)
- **Repository location**: `/repository/repository` (actual Kopia repository subdirectory)
- **Configured in**:
  - `ExternalSecret`: `KOPIA_REPOSITORY: filesystem:///repository/repository`
  - `kopia-init-job.yaml`: `--path=/repository/repository`
  - Volsync mover jobs: Automatically configured via MutatingAdmissionPolicy

## Enabling Backups in a New Namespace

To enable Volsync backups in a new namespace, you need to create a static PV and PVC that reference the shared CephFS volume.

### Step 1: Get the volumeHandle

The volumeHandle is the unique identifier for the CephFS subvolume. Get it from an existing PV:

```bash
kubectl get pv kopia-repository-pv-volsync-system -o jsonpath='{.spec.csi.volumeHandle}'
```

Expected output format: `0001-0024-407036f5-1f73-44ff-ba81-1f219b7a8a64-000000000000000b-841e604c-1dd5-4a09-8763-84e672d78c4e`

### Step 2: Create PV and PVC YAML

Create a file `kubernetes/apps/<tier>/<namespace>/volsync-repository-pvc/app/pvc.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/v1/persistentvolume.json
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kopia-repository-pv-<namespace>  # Replace <namespace>
spec:
  capacity:
    storage: 200Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: csi-cephfs-backups-sc
  csi:
    driver: cephfs.csi.ceph.com
    nodeStageSecretRef:
      name: csi-ceph-admin-secret
      namespace: ceph-csi
    volumeAttributes:
      clusterID: 407036f5-1f73-44ff-ba81-1f219b7a8a64
      fsName: backups
      storage.kubernetes.io/csiProvisionerIdentity: cephfs.csi.ceph.com
    volumeHandle: <PASTE-VOLUMEHANDLE-HERE>  # From step 1
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/v1/persistentvolumeclaim.json
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kopia
  namespace: <namespace>  # Replace <namespace>
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: csi-cephfs-backups-sc
  volumeName: kopia-repository-pv-<namespace>  # Must match PV name
  resources:
    requests:
      storage: 200Gi
```

### Step 3: Create Kustomization

Create `kubernetes/apps/<tier>/<namespace>/volsync-repository-pvc/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <namespace>  # Replace <namespace>
resources:
  - ./pvc.yaml
```

### Step 4: Create Flux Kustomization

Create `kubernetes/apps/<tier>/<namespace>/volsync-repository-pvc/ks.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app volsync-repository-pvc-<namespace>
  namespace: flux-system
spec:
  targetNamespace: <namespace>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  path: ./kubernetes/apps/<tier>/<namespace>/volsync-repository-pvc/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  wait: false
  interval: 30m
  retryInterval: 1m
  timeout: 5m
```

### Step 5: Apply via Flux

Commit and push the changes. Flux will create the PV and PVC in the target namespace.

### Step 6: Verify

```bash
# Check PVC is bound
kubectl get pvc -n <namespace> kopia

# Verify it uses the same volumeHandle
kubectl get pvc -n <namespace> kopia -o jsonpath='{.spec.volumeName}' | \
  xargs kubectl get pv -o jsonpath='{.spec.csi.volumeHandle}'
```

## Using Volsync in the New Namespace

Once the `kopia` PVC exists in the namespace, you can create ReplicationSource resources using the standard template:

```bash
cd kubernetes/apps/<tier>/<namespace>/<app>
flux create kustomization <app>-volsync \
  --namespace=<namespace> \
  --path=./kubernetes/components/volsync
```

The Volsync components will automatically use the `kopia` PVC in the namespace.

## Troubleshooting

### PVC Stuck in Pending

Check PV binding:
```bash
kubectl get pv | grep <namespace>
kubectl describe pvc -n <namespace> kopia
```

### Different volumeHandle

All PVs must use the same volumeHandle. If they differ, backups will be isolated per namespace.

### Permission Errors

The Volsync mover jobs run as UID 1000 by default. Ensure this user has write access to the CephFS volume.
