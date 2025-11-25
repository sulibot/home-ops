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

### After (With Layers):
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
  namespace: flux-system
  labels:
    layer: "1-network"    # Layer number with category
    component: cni         # Component type
    critical: "true"       # Mark as critical path
spec:
  dependsOn:
    - name: gateway-api-crds
      namespace: flux-system
```

## Layer Label Reference

### Layer 0: CRDs
```yaml
labels:
  layer: "0-crds"
  component: crds
  critical: "true"
```

Examples:
- `gateway-api-crds`
- `snapshot-controller-crds`

### Layer 1: Network
```yaml
labels:
  layer: "1-network"
  component: cni
  critical: "true"
```

Examples:
- `cilium`
- `multus`

### Layer 2: Storage & Security
```yaml
labels:
  layer: "2-foundation"
  component: storage  # or 'secrets'
  critical: "true"
```

Examples:
- `external-secrets` (component: secrets)
- `onepassword` (component: secrets)
- `ceph-csi-cephfs` (component: storage)
- `ceph-csi-rbd` (component: storage)
- `snapshot-controller` (component: storage)

### Layer 3: Core Services
```yaml
labels:
  layer: "3-core"
  component: platform
  critical: "true"
```

Examples:
- `cert-manager`
- `reloader`
- `metrics-server`
- `coredns`

### Layer 4: Network Services
```yaml
labels:
  layer: "4-network-services"
  component: ingress  # or 'dns', 'gateway'
```

Examples:
- `cilium-gateway` (component: gateway)
- `cilium-bgp` (component: routing)
- `external-dns` (component: dns)
- `certificates` (component: tls)

### Layer 5: Observability
```yaml
labels:
  layer: "5-observability"
  component: monitoring  # or 'logging', 'alerting'
```

Examples:
- `kube-prometheus-stack` (component: monitoring)
- `victoria-logs` (component: logging)
- `fluent-bit` (component: logging)
- `grafana` (component: monitoring)
- `gatus` (component: monitoring)

### Layer 6: Data Services
```yaml
labels:
  layer: "6-data"
  component: database  # or 'backup', 'cache'
```

Examples:
- `cloudnative-pg` (component: database)
- `volsync` (component: backup)
- `redis` (component: cache)

### Layer 7: Applications
```yaml
labels:
  layer: "7-apps"
  component: media  # or 'automation', 'security', etc.
```

Examples:
- `plex` (component: media)
- `sonarr` (component: media)
- `home-assistant` (component: automation)

## Benefits of Layering

### 1. Selective Reconciliation
```bash
# Reconcile all network layer apps
flux reconcile ks --with-source -l layer=1-network

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
When cluster recovery is needed, reconcile in layer order:
```bash
# Step 1: CRDs
flux reconcile ks --with-source -l layer=0-crds

# Step 2: Network
flux reconcile ks --with-source -l layer=1-network

# Step 3: Foundation (Storage & Security)
flux reconcile ks --with-source -l layer=2-foundation

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
├── 0-crds/
│   ├── gateway-api-crds/
│   └── snapshot-controller-crds/
├── 1-network/
│   ├── cilium/
│   └── multus/
├── 2-foundation/
│   ├── external-secrets/
│   ├── ceph-csi/
│   └── snapshot-controller/
├── 3-core/
│   ├── cert-manager/
│   └── reloader/
...
```

However, **labels are recommended** because:
- No need to restructure existing directories
- Can have multiple categorizations (layer + component)
- Easier to query and filter
- Less Git churn from moving files
