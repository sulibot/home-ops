# Flux Configuration

This directory contains Flux system configuration for managing the cluster.

## Structure

For now, Flux configuration lives in `kubernetes/clusters/production/` (legacy naming).

This will eventually be migrated to a cleaner structure:

```
kubernetes/flux/
├── config/
│   └── cluster-settings.yaml    # Cluster-specific ConfigMap
└── clusters/
    ├── cluster-101/              # Production
    │   ├── flux-system/
    │   └── kustomization.yaml
    └── cluster-102/              # Staging (future)
```

## Current Status

- Flux watches: `kubernetes/manifests/`
- Cluster config: `kubernetes/clusters/production/`
- Bootstrap: `kubernetes/bootstrap/` (manual, before Flux)

## Future Migration

When adding cluster-102 (staging), we'll reorganize to:
- Move `clusters/production/` → `flux/clusters/cluster-101/`
- Add `flux/clusters/cluster-102/`
- Use ConfigMaps for cluster-specific values
