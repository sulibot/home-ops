# Flux Application Layering - Implementation Examples

## Overview

This document shows how to add layer labels to your existing Kustomizations for better organization and dependency management.

## Example: Adding Layer Labels

### Before (Current):
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
  namespace: flux-system
spec:
  dependsOn:
    - name: gateway-api-crds
      namespace: flux-system
```

### After (With Domain Labels):
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
  namespace: flux-system
  labels:
    layer: "networking"    # domain label
    component: cni         # Component type
    critical: "true"       # Mark as critical path
spec:
  dependsOn:
    - name: gateway-api-crds
      namespace: flux-system
```

## Domain Label Reference

Use domain labels instead of numbered layers:

- `layer: "crds"`                (CRDs)
- `layer: "networking"`          (CNI/mesh/gateway)
- `layer: "foundation"`          (secrets/storage base)
- `layer: "core"`                (DNS/cert-manager/etc.)
- `layer: "network-services"`    (external-dns/tunnels/gateway services)
- `layer: "observability"`       (prom/loki/grafana/etc.)
- `layer: "data"`                (databases/backup/cache)
- `layer: "applications"`        (user apps)

Examples:
- `gateway-api-crds` → layer: "crds"
- `cilium` → layer: "networking"
- `external-secrets` → layer: "foundation"
- `cert-manager` → layer: "core"
- `external-dns` → layer: "network-services"
- `kube-prometheus-stack` → layer: "observability"
- `cloudnative-pg` → layer: "data"
- `plex` → layer: "applications"

## Benefits of Layering

### 1. Selective Reconciliation
```bash
# Reconcile all networking domain apps
flux reconcile ks --with-source -l layer=networking

# Reconcile only critical infrastructure
flux reconcile ks --with-source -l critical=true

# Reconcile storage components
flux reconcile ks --with-source -l component=storage
```

### 2. Monitoring & Dashboards
```promql
# Count kustomizations by layer
count by (layer) (gotk_kustomize_info)

# Alert on critical layer failures
gotk_kustomize_status_condition{type="Ready",status="False",critical="true"}
```

### 3. Troubleshooting
When cluster recovery is needed, reconcile in domain order:
```bash
# Step 1: CRDs
flux reconcile ks --with-source -l layer=crds

# Step 2: Network
flux reconcile ks --with-source -l layer=networking

# Step 3: Foundation (Storage & Security)
flux reconcile ks --with-source -l layer=foundation

# ... and so on
```

### 4. GitOps Workflow
```yaml
# In CI/CD, validate dependencies match layers
- name: Validate Dependencies
  run: |
    # Ensure layer N only depends on layer N-1 or lower
    ./scripts/validate-layers.sh
```

## Migration Strategy

1. **Phase 1**: Add labels to critical infrastructure (layers 0-3)
2. **Phase 2**: Add labels to network services (layer 4)
3. **Phase 3**: Add labels to observability (layer 5)
4. **Phase 4**: Add labels to applications (layers 6-7)

Start with a few key Kustomizations, test the labels work for filtering, then gradually expand.

## Alternative: Directory-Based Layers

If you prefer directory structure over labels, you could reorganize:

```
kubernetes/apps/
├── crds/
│   ├── gateway-api-crds/
│   └── snapshot-controller-crds/
├── networking/
│   ├── cilium/
│   └── multus/
├── foundation/
│   ├── external-secrets/
│   ├── ceph-csi/
│   └── snapshot-controller/
├── core/
│   ├── cert-manager/
│   └── reloader/
...
```

However, **labels are recommended** because:
- No need to restructure existing directories
- Can have multiple categorizations (layer + component)
- Easier to query and filter
- Less Git churn from moving files
