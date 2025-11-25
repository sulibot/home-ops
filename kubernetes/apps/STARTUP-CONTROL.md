# Flux Startup Control & Dependency Isolation

## Problem Statement

When Cilium has a hiccup, many apps pause reconciliation even if they don't strictly need Cilium to be Ready. This creates cascading failures and slow recovery.

## Solutions

### 1. Use Health Checks Strategically

Only use `healthChecks` on critical infrastructure that MUST be healthy:

```yaml
# Critical: Cilium MUST be healthy before proceeding
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
spec:
  wait: true
  timeout: 10m
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: cilium
      namespace: kube-system
```

```yaml
# Non-Critical: Apps can reconcile even if pods aren't perfectly healthy
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: plex
spec:
  wait: false  # ← Don't wait for health, just apply
  # No healthChecks - let the app manage its own health
  dependsOn:
    - name: cilium-gateway  # Only depends on gateway, not Cilium itself
    - name: ceph-csi
```

### 2. Minimize Dependencies

Only add `dependsOn` for **actual runtime dependencies**:

#### Before (Too Broad):
```yaml
spec:
  dependsOn:
    - name: cilium              # ← Blocks if CNI has issues
    - name: cert-manager        # ← Only needed if using cert-manager certs
    - name: external-secrets    # ← Only needed if using ExternalSecret
    - name: ceph-csi           # ← Only needed if using Ceph volumes
```

#### After (Minimal):
```yaml
spec:
  dependsOn:
    - name: cilium-gateway     # ← Only blocks if gateway not ready
    - name: ceph-csi-cephfs    # ← Only blocks if volume driver not ready
    # No cert-manager - HTTPRoute doesn't need it directly
    # No external-secrets - app manages its own secrets after creation
```

### 3. Layer Dependencies with Tolerances

Use `retryInterval` and increased `timeout` for layers that can tolerate delays:

```yaml
# Layer 0-1: Critical Infrastructure (strict)
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cilium
spec:
  interval: 30m
  retryInterval: 2m
  timeout: 10m
  wait: true

---
# Layer 4-7: Applications (lenient)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: plex
spec:
  interval: 1h           # ← Less frequent checks
  retryInterval: 5m      # ← Wait longer between retries
  timeout: 15m           # ← More time to succeed
  wait: false            # ← Don't block on health
  dependsOn:
    - name: cilium-gateway
```

### 4. Progressive Dependencies

Break apps into multiple Kustomizations if they have different dependency needs:

```yaml
# Step 1: Install CRDs and base resources (no dependencies)
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-base
spec:
  path: ./kubernetes/apps/default/plex/base
  # No dependencies - can install CRDs anytime

---
# Step 2: Install app (depends on infrastructure)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: app-workload
spec:
  path: ./kubernetes/apps/default/plex/app
  dependsOn:
    - name: app-base
    - name: cilium-gateway
    - name: ceph-csi-cephfs
```

### 5. Use Suspend for Maintenance

During infrastructure work, suspend non-critical apps:

```bash
# Before working on Cilium
flux suspend kustomization -l layer=7-apps

# Work on Cilium...
kubectl rollout restart -n kube-system daemonset/cilium

# Resume apps
flux resume kustomization -l layer=7-apps
```

## Recommended Dependency Tree

### Critical Path (Must be sequential)
```
gateway-api-crds
  ↓
cilium
  ↓
cilium-gateway / cilium-bgp / cilium-ippool (parallel)
  ↓
external-dns
```

### Storage Path (Can run in parallel with network)
```
snapshot-controller-crds
  ↓
ceph-csi-* / snapshot-controller (parallel)
```

### Security Path (Can run in parallel with network)
```
external-secrets
  ↓
onepassword
  ↓
cert-manager
  ↓
certificates
```

### Applications (Minimal dependencies)
```
plex:
  dependsOn:
    - cilium-gateway  # For HTTPRoute
    - ceph-csi-cephfs # For storage

sonarr:
  dependsOn:
    - cilium-gateway  # For HTTPRoute
    - ceph-csi-cephfs # For storage
    # Note: No dependency on Plex or other apps
```

## Best Practices for Resilience

### 1. Don't Depend on Cilium Directly

Apps should depend on **specific Cilium features**, not Cilium itself:

❌ **Bad:**
```yaml
dependsOn:
  - name: cilium  # Too broad - blocks on ANY Cilium issue
```

✅ **Good:**
```yaml
dependsOn:
  - name: cilium-gateway  # Specific - only blocks if Gateway API not ready
```

### 2. Use Force for Non-Critical Updates

Allow non-critical apps to update even if dependencies aren't perfect:

```yaml
spec:
  force: true  # Apply even if dependencies have issues
  dependsOn:
    - name: cilium-gateway
```

### 3. Separate CRDs from Implementations

```yaml
# CRDs can install anytime
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager-crds
spec:
  prune: false  # Never delete CRDs
  # No dependencies

---
# Implementation depends on CRDs
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager
spec:
  dependsOn:
    - name: cert-manager-crds
    - name: cilium
```

### 4. Health Check Only What Matters

```yaml
# Check that Cilium DaemonSet is running
healthChecks:
  - apiVersion: apps/v1
    kind: DaemonSet
    name: cilium
    namespace: kube-system
  # Don't check every Cilium pod's perfect health
  # Don't check Cilium Operator health unless critical
```

## Example: Refactored Plex Kustomization

### Before (Fragile):
```yaml
spec:
  wait: true
  dependsOn:
    - name: cilium
    - name: cert-manager
    - name: external-secrets
    - name: onepassword
    - name: ceph-csi
```

### After (Resilient):
```yaml
spec:
  interval: 1h
  retryInterval: 5m
  timeout: 15m
  wait: false  # Don't block cluster on one app's health
  dependsOn:
    - name: cilium-gateway  # Only what's truly needed
      namespace: flux-system
    - name: ceph-csi-cephfs  # Only what's truly needed
      namespace: flux-system
  # Removed: cert-manager (gateway handles certs)
  # Removed: external-secrets (not used by this app)
  # Removed: cilium (too broad)
```

## Monitoring & Alerting

Monitor dependency blocking:

```promql
# Alert if apps are blocked waiting on dependencies
count by (name) (
  gotk_kustomize_condition{type="Ready", status="Unknown"}
) > 0

# Alert if critical infrastructure is down
gotk_kustomize_condition{
  type="Ready",
  status="False",
  name=~"cilium|ceph-csi|external-secrets",
  critical="true"
}
```

## Recovery Workflow

When Cilium has issues:

```bash
# 1. Check what's blocked
flux get kustomizations | grep -v "True"

# 2. Suspend non-critical apps
flux suspend ks -l layer=7-apps

# 3. Fix Cilium
kubectl rollout restart -n kube-system daemonset/cilium

# 4. Wait for Cilium
flux reconcile ks cilium --with-source

# 5. Resume layer by layer
flux resume ks -l layer=4-network-services
flux resume ks -l layer=5-observability
flux resume ks -l layer=7-apps
```

## Implementation Checklist

- [ ] Audit all `dependsOn` - remove unnecessary deps
- [ ] Set `wait: false` on non-critical apps
- [ ] Remove `healthChecks` from apps (keep only on infrastructure)
- [ ] Depend on specific features (cilium-gateway) not broad components (cilium)
- [ ] Add `retryInterval` and longer `timeout` to apps
- [ ] Separate CRDs from implementations
- [ ] Add layer labels for easier suspend/resume operations
- [ ] Create runbooks for Cilium maintenance
