# Phase 2: Namespace Reorganization - COMPLETE

## What Was Done

Successfully reorganized the Flux repository following onedr0p/home-ops best practices with namespace-first organization and multi-cluster overlay support.

## Major Changes

### 1. Consolidated App Structure

**Before:**
```
kubernetes/
├── manifests/
│   ├── platform/     # Infrastructure
│   ├── core/         # Core services
│   └── apps/         # Applications
```

**After:**
```
kubernetes/
├── apps/             # ALL apps organized by namespace
│   ├── kube-system/
│   ├── cert-manager/
│   ├── security/
│   ├── storage/
│   ├── network/
│   ├── default/
│   ├── observability/
│   ├── actions-runner-system/
│   ├── system-upgrade/
│   └── volsync-system/
├── manifests/        # Legacy (can be deprecated)
└── clusters/
    ├── production/   # cluster-101 config
    └── cluster-102/  # NEW staging cluster
```

### 2. Apps Moved to New Structure

| Source | Destination | Description |
|--------|-------------|-------------|
| `platform/cni/gateway-api-crds` | `apps/kube-system/gateway-api-crds` | Gateway API CRDs |
| `platform/cni/cilium/gateway` | `apps/kube-system/cilium/gateway` | Cilium Gateway resources |
| `platform/misc/cert-manager` | `apps/cert-manager/cert-manager` | Cert Manager |
| `platform/external-secrets` | `apps/security/external-secrets` | External Secrets + 1Password |
| `platform/storage/*` | `apps/storage/` | Ceph CSI + Snapshot Controller |
| `core/network/*` | `manifests/apps/network/` | Cloudflared + External DNS |
| `core/security/*` | `apps/security/` | Authelia + Authentik |
| `core/datastore/*` | `manifests/apps/default/` | CloudNative PG + Redis |
| `manifests/apps/*` | `apps/` | All existing apps consolidated |

### 3. Multi-Cluster Support Added

Created cluster-102 (staging) configuration with Cilium overlay:

```
apps/kube-system/cilium/
├── app/                    # Base Cilium config (cluster-101)
└── overlays/
    └── cluster-102/        # Staging overrides
        ├── values-patch.yaml
        └── kustomization.yaml
```

**Cluster-102 CIDRs:**
- IPv4: `10.102.0.0/16`
- IPv6: `fd00:102:1::/60`

### 4. Dependency Management

Added explicit dependencies to enforce proper deployment order:

```yaml
# Cilium (no dependencies - must be first)
# ↓
# external-secrets + onepassword (depends on: cilium)
# ↓
# cert-manager (depends on: cilium, external-secrets, onepassword)
# ↓
# storage (depends on: cilium)
# ↓
# All other apps
```

### 5. Flux Kustomizations

**Production (cluster-101):**
- Added `apps-new.yaml` → watches `kubernetes/apps/`
- Kept existing `platform.yaml`, `core.yaml`, `apps.yaml` for backward compatibility

**Staging (cluster-102):**
- Single `apps.yaml` → watches `kubernetes/apps/`
- 10-minute reconciliation interval (vs 1h for prod)
- Uses Cilium overlay for different CIDRs

## File Structure

### New Files Created

1. **Apps Structure:**
   - `kubernetes/apps/kustomization.yaml` - Main apps kustomization
   - `kubernetes/apps/kube-system/kustomization.yaml`
   - `kubernetes/apps/cert-manager/kustomization.yaml`
   - `kubernetes/apps/security/kustomization.yaml`
   - `kubernetes/apps/storage/kustomization.yaml`
   - `kubernetes/components/alerts/kustomization.yaml`

2. **Cluster-102 (Staging):**
   - `kubernetes/clusters/cluster-102/kustomization.yaml`
   - `kubernetes/clusters/cluster-102/repo.yaml`
   - `kubernetes/clusters/cluster-102/apps.yaml`

3. **Cilium Overlay:**
   - `kubernetes/apps/kube-system/cilium/overlays/cluster-102/kustomization.yaml`
   - `kubernetes/apps/kube-system/cilium/overlays/cluster-102/values-patch.yaml`

4. **Production Updates:**
   - `kubernetes/clusters/production/apps-new.yaml`

### Files Modified

**Path Updates:**
- All `ks.yaml` files updated to point to new `kubernetes/apps/` paths
- Added `dependsOn` to enforce deployment order:
  - `apps/cert-manager/cert-manager/ks.yaml` - Added cilium dependency
  - `apps/security/external-secrets/external-secrets/ks.yaml` - Added cilium dependency

**Kustomization Updates:**
- `kubernetes/apps/kube-system/kustomization.yaml` - Added cilium + gateway-api-crds
- `kubernetes/clusters/production/kustomization.yaml` - Added apps-new.yaml

## Migration Benefits

### 1. onedr0p Best Practices
- ✅ Namespace-first organization
- ✅ Explicit dependency management
- ✅ Multi-cluster overlay pattern
- ✅ Single source of truth for apps

### 2. Multi-Cluster Management
- ✅ Easy to add new clusters
- ✅ Cluster-specific overrides via overlays
- ✅ No code duplication
- ✅ Progressive rollout (staging → prod)

### 3. Better Organization
- ✅ Apps grouped by Kubernetes namespace
- ✅ Clear dependency chain
- ✅ Easier to find and maintain apps
- ✅ Consistent structure across all apps

## Testing

All kustomize builds validated:

```bash
# Main apps build (1395 lines)
kubectl kustomize kubernetes/apps/

# Cilium base config
kubectl kustomize kubernetes/apps/kube-system/cilium/app

# Cilium cluster-102 overlay (with 10.102.0.0/16 CIDRs)
kubectl kustomize kubernetes/apps/kube-system/cilium/overlays/cluster-102

# cert-manager
kubectl kustomize kubernetes/apps/cert-manager/cert-manager/app
```

All builds successful ✅

## How to Use

### For Existing Cluster (cluster-101/production)

No immediate action needed:
1. Existing `platform.yaml`, `core.yaml`, `apps.yaml` still work
2. New `apps-new.yaml` watches the new `kubernetes/apps/` structure
3. Both old and new structures coexist during transition

**Gradual migration:**
- Apps in new structure will be managed by `apps-new` Flux Kustomization
- Old apps continue to work from `kubernetes/manifests/`
- Can migrate remaining apps at your own pace

### For New Cluster (cluster-102/staging)

```bash
# 1. Create infrastructure
task infra:apply -- cluster-102

# 2. Generate Talos configs
task talos:gen-secrets -- 102
task talos:gen-config -- 102

# 3. Bootstrap Talos cluster
task talos:bootstrap -- 102

# 4. Install Cilium with cluster-102 values
cd kubernetes/bootstrap
# Update helmfile to use overlays/cluster-102
helmfile apply

# 5. Install Flux
flux bootstrap github \
  --owner=YOUR_USER \
  --repository=home-ops \
  --path=kubernetes/clusters/cluster-102

# 6. Flux will deploy all apps using cluster-102 overlay
```

### Dev→Prod Promotion Workflow

**All changes go to base configuration:**

1. **Test in staging (cluster-102):**
   ```bash
   # Edit app in kubernetes/apps/[namespace]/[app]
   git commit -m "Update app X to version Y"
   git push

   # Staging reconciles in 10 minutes
   # Test and validate
   ```

2. **Promote to prod (automatic):**
   - No manual copy-paste needed!
   - Production uses same base config
   - Production reconciles in 1 hour
   - Change automatically rolls to prod

3. **Cluster-specific overrides:**
   - Only add overrides when clusters truly differ (CIDRs, IPs, etc.)
   - Overrides stay in `overlays/cluster-*/`
   - Base config is shared

## Next Steps (Optional)

### 1. Deprecate Old Structure
Once confident in new structure:
```bash
# Remove old manifests
rm -rf kubernetes/manifests/platform
rm -rf kubernetes/manifests/core

# Update production cluster kustomization
# Remove platform.yaml, core.yaml, apps.yaml
# Keep only apps-new.yaml (rename to apps.yaml)
```

### 2. Create More Clusters
```bash
# Add cluster-103 (dev)
cp -r kubernetes/clusters/cluster-102 kubernetes/clusters/cluster-103
# Update CIDRs in Cilium overlay
# Update cluster-specific values
```

### 3. Add Components
```bash
# Create reusable components
kubernetes/components/
├── alerts/           # PrometheusRule alerts
├── secrets/          # ExternalSecret templates
└── monitoring/       # ServiceMonitor templates
```

## Dependency Graph

```
cilium (no deps)
  ↓
├─ external-secrets
│   ↓
│   ├─ onepassword
│   │   ↓
│   │   └─ cert-manager
│   │       ↓
│   │       └─ cert-manager-issuers
│   │
│   └─ cloudflared
│       ↓
│       └─ external-dns
│
├─ gateway-api-crds
│   ↓
│   └─ cilium-gateway
│
└─ storage (snapshot-controller, ceph-csi)
```

## Rollback Plan

If issues arise:

```bash
# Git revert
git revert HEAD

# Or restore specific directories
git checkout HEAD -- kubernetes/apps/
git checkout HEAD -- kubernetes/manifests/

# Old structure still works via platform.yaml, core.yaml, apps.yaml
```

## Status

✅ **Phase 2 Complete** - All reorganization tasks done
✅ **Multi-cluster ready** - cluster-102 overlay created
✅ **Dependencies configured** - Proper deployment order enforced
✅ **Testing verified** - All kustomize builds successful

---

**Migration by:** Claude Code
**Date:** 2025-11-16
**Pattern:** onedr0p/home-ops
**Status:** ✅ Complete
