# Phase 2: Namespace Reorganization Plan

## Current Situation

You have a **hybrid structure**:

```
kubernetes/
├── manifests/
│   ├── apps/                          # ✅ ALREADY namespace-organized!
│   │   ├── kube-system/              # System apps
│   │   ├── default/                   # User apps (30+ apps)
│   │   ├── network/                   # Network apps
│   │   ├── observability/             # Monitoring apps
│   │   ├── actions-runner-system/
│   │   ├── system-upgrade/
│   │   └── volsync-system/
│   │
│   ├── platform/                      # ❌ NEEDS TO MOVE
│   │   ├── cni/                      # → kube-system
│   │   ├── storage/                   # → storage namespace
│   │   ├── misc/cert-manager/         # → cert-manager namespace
│   │   └── external-secrets/          # → security namespace
│   │
│   └── core/                          # ❌ NEEDS TO MOVE
│       └── network/                   # → network namespace (merge with apps/network)
│
└── apps/                              # ✅ NEW onedr0p structure (Cilium already here)
    └── kube-system/cilium/
```

## Strategy: Gradual Migration

Instead of moving everything at once (risky!), we'll do a **phased approach**:

### Phase 2a: Move Critical Infrastructure (Do This Now)
1. Move `platform/cni/` → `apps/kube-system/`
2. Move `platform/misc/cert-manager/` → `apps/cert-manager/`
3. Move `platform/external-secrets/` → `apps/security/`
4. Move `platform/storage/` → `apps/storage/`
5. Move `core/network/` → Merge with `manifests/apps/network/`

### Phase 2b: Consolidate (Later)
1. Move `manifests/apps/*` → `apps/*`
2. Delete empty `manifests/` directory
3. Update all Flux Kustomizations to point to `kubernetes/apps/`

### Phase 2c: Add Dependencies (After consolidation)
Add `dependsOn` to all `ks.yaml` files

## Why Gradual?

- ✅ **Lower risk** - Test each move separately
- ✅ **Easier to rollback** - One component at a time
- ✅ **Working cluster** - No disruption to production
- ✅ **Validate** - Ensure Flux reconciles correctly after each move

## Detailed Migration Steps - Phase 2a

### Step 1: Move Cilium (Gateway API components)

```bash
# Cilium app is already in kubernetes/apps/kube-system/cilium/
# Move gateway components
mv kubernetes/manifests/platform/cni/cilium/gateway/ \\
   kubernetes/apps/kube-system/cilium/

# Move gateway-api-crds
mv kubernetes/manifests/platform/cni/gateway-api-crds/ \\
   kubernetes/apps/kube-system/
```

### Step 2: Move cert-manager

```bash
mkdir -p kubernetes/apps/cert-manager/cert-manager
mv kubernetes/manifests/platform/misc/cert-manager/app/ \\
   kubernetes/apps/cert-manager/cert-manager/
mv kubernetes/manifests/platform/misc/cert-manager/ks.yaml \\
   kubernetes/apps/cert-manager/cert-manager/
mv kubernetes/manifests/platform/misc/cert-manager/issuers/ \\
   kubernetes/apps/cert-manager/

# Update ks.yaml path
sed -i '' 's|./kubernetes/manifests/platform/misc/cert-manager/app|./kubernetes/apps/cert-manager/cert-manager/app|g' \\
   kubernetes/apps/cert-manager/cert-manager/ks.yaml
```

### Step 3: Move External Secrets (→ security namespace)

```bash
mkdir -p kubernetes/apps/security
mv kubernetes/manifests/platform/external-secrets/ \\
   kubernetes/apps/security/

# Update paths in ks.yaml files
find kubernetes/apps/security/external-secrets -name "ks.yaml" -exec \\
  sed -i '' 's|./kubernetes/manifests/platform/external-secrets|./kubernetes/apps/security/external-secrets|g' {} \\;
```

### Step 4: Move Storage

```bash
mkdir -p kubernetes/apps/storage
mv kubernetes/manifests/platform/storage/ \\
   kubernetes/apps/storage/

# Update paths
find kubernetes/apps/storage -name "ks.yaml" -exec \\
  sed -i '' 's|./kubernetes/manifests/platform/storage|./kubernetes/apps/storage|g' {} \\;
```

### Step 5: Merge Network Apps

```bash
# Core network apps (cloudflared, external-dns) → apps/network
mv kubernetes/manifests/core/network/cloudflared/ \\
   kubernetes/manifests/apps/network/
mv kubernetes/manifests/core/network/external-dns/ \\
   kubernetes/manifests/apps/network/

# Update paths
find kubernetes/manifests/apps/network -name "ks.yaml" -exec \\
  sed -i '' 's|./kubernetes/manifests/core/network|./kubernetes/manifests/apps/network|g' {} \\;
```

### Step 6: Update Cluster Flux Kustomizations

Update `kubernetes/clusters/production/*.yaml` to point to new paths:

```yaml
# platform.yaml - now points to apps/
spec:
  path: ./kubernetes/apps/kube-system

# apps.yaml - already correct
spec:
  path: ./kubernetes/manifests/apps
```

## Phase 2b: Full Consolidation (Future)

Once Phase 2a is stable:

```bash
# Move everything from manifests/apps → apps/
mv kubernetes/manifests/apps/* kubernetes/apps/

# Delete old structure
rm -rf kubernetes/manifests/

# Update all paths to ./kubernetes/apps/
```

## Dependencies to Add (Phase 2c)

### Infrastructure Dependencies

```yaml
# Cilium - no dependencies (must be first)
# ✓ Already created

# cert-manager - depends on cilium
spec:
  dependsOn:
    - name: cilium
      namespace: flux-system

# external-secrets - depends on cilium
spec:
  dependsOn:
    - name: cilium
      namespace: flux-system

# storage (ceph-csi) - depends on cilium, snapshot-controller
spec:
  dependsOn:
    - name: cilium
      namespace: flux-system
    - name: snapshot-controller
      namespace: flux-system
```

### Application Dependencies

```yaml
# Apps with databases - depend on storage
spec:
  dependsOn:
    - name: ceph-csi
      namespace: flux-system
    - name: cert-manager  # If using TLS
      namespace: flux-system

# Apps with secrets - depend on external-secrets
spec:
  dependsOn:
    - name: external-secrets
      namespace: flux-system
```

## cluster-102 (Staging) Setup

### Cilium Overlay for cluster-102

```bash
mkdir -p kubernetes/apps/kube-system/cilium/overlays/cluster-102

# Create values patch
cat > kubernetes/apps/kube-system/cilium/overlays/cluster-102/values-patch.yaml <<EOF
---
# Cluster-102 (staging) specific values
# Different CIDRs from cluster-101

ipv4NativeRoutingCIDR: 10.102.0.0/16
ipv6NativeRoutingCIDR: fd00:102:1::/60

# Optional: More aggressive update interval for testing
EOF

# Create kustomization
cat > kubernetes/apps/kube-system/cilium/overlays/cluster-102/kustomization.yaml <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kube-system

resources:
  - ../../app

patches:
  - path: values-patch.yaml
    target:
      kind: ConfigMap
      name: cilium-helm-values
EOF
```

### Cluster-102 Flux Config

```bash
mkdir -p kubernetes/flux/clusters/cluster-102

# Bootstrap values for cluster-102
cp -r kubernetes/bootstrap/ kubernetes/bootstrap-102/
# Update CIDRs in kubernetes/bootstrap-102/values/cilium.yaml

# Flux kustomization for cluster-102
cat > kubernetes/flux/clusters/cluster-102/apps.yaml <<EOF
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m  # Faster updates for staging
  path: ./kubernetes/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  wait: false
EOF
```

## Rollback Plan

If anything breaks:

```bash
# Revert Git commit
git revert HEAD

# Or manually revert specific moves
git checkout HEAD -- kubernetes/manifests/platform/
git checkout HEAD -- kubernetes/apps/
```

## Testing Checklist

After each move:

- [ ] `kubectl kustomize kubernetes/apps/[namespace]/[app]/app` builds successfully
- [ ] Flux reconciles: `flux reconcile kustomization [app]`
- [ ] Application is healthy: `kubectl get helmrelease -A`
- [ ] No breaking changes to running apps

## Current Status

- ✅ Phase 1: Bootstrap pattern created
- ⏳ Phase 2a: Ready to execute
- ⏸️ Phase 2b: Pending Phase 2a completion
- ⏸️ Phase 2c: Pending Phase 2b completion

## Recommendation

**Start with Phase 2a** - Move critical infrastructure only. Once stable, proceed with full consolidation.

For cluster-102, **wait until Phase 2b is complete** so you don't have to migrate twice.
