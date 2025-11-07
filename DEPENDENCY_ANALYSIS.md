# Flux Kustomization Dependency Analysis Report

**Generated:** 2025-11-07
**Repository:** home-ops
**Total Kustomizations Analyzed:** 81

---

## Executive Summary

### ✅ GOOD NEWS: No Circular Dependencies Found!

The dependency analysis completed successfully with **ZERO circular dependencies** detected in your Flux Kustomization manifests.

### Key Findings

1. **No Circular Dependencies** - All dependency chains are properly structured
2. **One Missing Dependency** - Reference to non-existent `openebs` kustomization
3. **Longest Chain: 6 levels** - Reasonable depth, not excessive
4. **Well-structured Platform** - Critical components have clean dependency hierarchies

---

## 1. Circular Dependency Analysis

### Result: ✅ PASSED

**No circular dependencies detected.**

A circular dependency would look like: `A → B → C → A`

Your dependency graph is a proper DAG (Directed Acyclic Graph), which means Flux can safely reconcile all kustomizations in the correct order.

---

## 2. Missing Dependencies

### ⚠️ WARNING: 1 Missing Dependency Reference

**Issue:**
- **Kustomization:** `actions-runner-controller-runners`
- **Missing Dependency:** `openebs`
- **Expected Namespace:** `openebs-system`
- **File:** `/Users/sulibot/repos/github/home-ops/kubernetes/manifests/apps/actions-runner-system/actions-runner-controller/ks.yaml`

**Impact:**
The `actions-runner-controller-runners` kustomization has a dependency on `openebs` which does not exist as a kustomization in your cluster. This will cause Flux to wait indefinitely for the `openebs` dependency to be ready.

**Recommendation:**
- If OpenEBS is no longer used, remove the dependency reference
- If OpenEBS should exist, create the missing kustomization manifest
- If the dependency is incorrect, update to the correct dependency name

---

## 3. Longest Dependency Chains

The following shows the top 10 longest dependency chains in your cluster:

### Chain 1 (Length: 6)
```
certificates-export
  → certificates-import
    → cilium-gateway
      → cert-manager
        → onepassword
          → cilium
            → gateway-api-crds
```

### Chain 2-4 (Length: 5)
```
cloudflare-dns → cilium-gateway → cert-manager → onepassword → cilium → gateway-api-crds
echo → cilium-gateway → cert-manager → onepassword → cilium → gateway-api-crds
certificates-import → cilium-gateway → cert-manager → onepassword → cilium → gateway-api-crds
```

### Chain 5-7 (Length: 5)
```
certificates-export → certificates-import → cert-manager → onepassword → cilium → gateway-api-crds
certificates-export → certificates-import → cilium-gateway → cert-manager → onepassword → external-secrets
external-dns → cilium-gateway → cert-manager → onepassword → cilium → gateway-api-crds
```

### Chain 8-10 (Length: 4)
```
kopia → volsync → ceph-csi-cephfs → cilium → gateway-api-crds
volsync-maintenance → volsync → ceph-csi-cephfs → cilium → gateway-api-crds
grafana-instance → grafana → onepassword → cilium → gateway-api-crds
```

**Analysis:**
- Maximum chain depth of 6 is reasonable and manageable
- Most chains originate from networking components (certificates, DNS)
- Foundation components (gateway-api-crds, external-secrets, ceph-csi) are properly at the leaf level

---

## 4. Critical Component Dependencies

### Platform Layer Components

#### gateway-api-crds (Foundation)
- **Depends on:** None (root node)
- **Required by:** cilium (1 component)
- **Role:** Provides Gateway API CRDs for Cilium
- **Status:** ✅ Properly positioned as a root dependency

#### cilium (CNI)
- **Depends on:** gateway-api-crds
- **Required by:** 11 components
  - metrics-server
  - multus
  - coredns
  - spegel
  - fluent-bit
  - ceph-csi-rbd
  - ceph-csi-cephfs
  - onepassword
  - cloudflared
  - external-dns
  - And 1 more...
- **Role:** Core networking CNI
- **Status:** ✅ Critical platform component with many dependents

#### external-secrets (Secrets Management)
- **Depends on:** None (root node)
- **Required by:** 6 components
  - onepassword
  - cilium-gateway
  - cert-manager
  - external-dns
  - cloudflared
  - cloudflare-dns
- **Role:** External secrets operator
- **Status:** ✅ Properly positioned as root dependency

#### onepassword (Secrets Provider)
- **Depends on:** cilium, external-secrets
- **Required by:** 29 components (highest dependency count!)
  - kopia
  - kube-prometheus-stack
  - grafana
  - gatus
  - unpoller
  - home-assistant
  - plex
  - sonarr
  - radarr
  - prowlarr
  - And 19 more...
- **Role:** 1Password operator for secret injection
- **Status:** ✅ Critical - most dependent component in cluster

#### cert-manager (Certificate Management)
- **Depends on:** external-secrets, onepassword
- **Required by:** 2 components
  - certificates-import
  - cilium-gateway
- **Role:** Certificate management
- **Status:** ✅ Proper dependency chain

#### cilium-gateway (Gateway)
- **Depends on:** cilium, cert-manager, external-secrets
- **Required by:** 4 components
  - cloudflare-dns
  - echo
  - certificates-import
  - external-dns
- **Role:** Cilium Gateway API implementation
- **Status:** ✅ Properly depends on all prerequisites

### Storage Layer Components

#### snapshot-controller-crds (Storage Foundation)
- **Depends on:** None (root node)
- **Required by:** 3 components
  - snapshot-controller
  - ceph-csi-cephfs
  - ceph-csi-rbd
- **Role:** Volume snapshot CRDs
- **Status:** ✅ Proper root dependency

#### ceph-csi (Storage Configuration)
- **Depends on:** None (root node)
- **Required by:** 29 components
  - kube-prometheus-stack
  - grafana-instance
  - victoria-logs
  - mosquitto
  - fusion
  - home-assistant
  - plex
  - immich
  - emby
  - And 20 more...
- **Role:** Ceph CSI shared configuration
- **Status:** ✅ Critical storage dependency

#### ceph-csi-shared-secret (Storage Secrets)
- **Depends on:** None (root node)
- **Required by:** 2 components
  - ceph-csi-cephfs
  - ceph-csi-rbd
- **Role:** Shared Ceph credentials
- **Status:** ✅ Proper root dependency

#### ceph-csi-rbd (Block Storage)
- **Depends on:** cilium, snapshot-controller-crds, ceph-csi-shared-secret
- **Required by:** 0 components
- **Role:** Ceph RBD driver
- **Status:** ⚠️ No dependents - verify if RBD storage class is used

#### ceph-csi-cephfs (Filesystem Storage)
- **Depends on:** cilium, snapshot-controller-crds, ceph-csi-shared-secret
- **Required by:** 2 components
  - volsync
  - ceph-csi-shared-storage
- **Role:** CephFS driver
- **Status:** ✅ Used by volsync for backups

---

## 5. Dependency Graph Visualization

### Foundation Layer (Root Nodes - No Dependencies)
```
gateway-api-crds
external-secrets
snapshot-controller-crds
ceph-csi
ceph-csi-shared-secret
```

### Platform Layer
```
gateway-api-crds → cilium → onepassword → cert-manager → cilium-gateway
                      ↓
external-secrets ────┘
```

### Storage Layer
```
snapshot-controller-crds → ceph-csi-cephfs → volsync → kopia
                                  ↓
ceph-csi-shared-secret ──────────┘

snapshot-controller-crds → ceph-csi-rbd
                                  ↓
ceph-csi-shared-secret ──────────┘
```

### Application Layer Dependencies
```
Most applications depend on:
  - onepassword (for secrets)
  - ceph-csi (for storage)
  - volsync (for backups, if applicable)
```

---

## 6. Recommendations

### Immediate Action Required

1. **Fix Missing Dependency**
   - Review `actions-runner-controller-runners` dependency on `openebs`
   - File: `/kubernetes/manifests/apps/actions-runner-system/actions-runner-controller/ks.yaml`
   - Action: Remove reference or create missing kustomization

### Best Practices Observed ✅

1. **Clean Separation of Concerns**
   - Platform components (networking, secrets, certificates) are properly layered
   - Storage components have clear dependency hierarchy
   - Applications depend on platform services

2. **No Circular Dependencies**
   - All dependency chains are acyclic
   - Flux can reconcile in proper order

3. **Reasonable Chain Depth**
   - Maximum depth of 6 is manageable
   - No excessively deep dependency chains

### Potential Improvements

1. **ceph-csi Naming Clarity**
   - Consider renaming `ceph-csi` to `ceph-csi-config` or `ceph-csi-shared`
   - Current name is generic but contains shared config
   - Other ceph-csi components (rbd, cephfs) are more specific

2. **Document Critical Dependencies**
   - `onepassword` has 29 dependents (critical component)
   - `ceph-csi` has 29 dependents (critical component)
   - Consider adding health checks to these critical components

3. **Verify RBD Usage**
   - `ceph-csi-rbd` has no kustomization dependents
   - Verify if RBD storage class is actually used by workloads
   - Consider consolidating if only CephFS is needed

---

## 7. Component Dependency Summary

### Components with Most Dependents
1. **onepassword**: 29 dependents (secrets)
2. **ceph-csi**: 29 dependents (storage)
3. **cilium**: 11 dependents (networking)
4. **external-secrets**: 6 dependents (secrets management)
5. **cilium-gateway**: 4 dependents (ingress)

### Components with Most Dependencies
1. **certificates-export**: 2 dependencies
2. **certificates-import**: 2 dependencies
3. **cilium-gateway**: 3 dependencies
4. **ceph-csi-rbd**: 3 dependencies
5. **ceph-csi-cephfs**: 3 dependencies

### Leaf Nodes (No Dependents)
- ceph-csi-rbd
- Most application kustomizations (expected)

---

## Conclusion

Your Flux Kustomization dependency structure is **well-architected** with:
- ✅ No circular dependencies
- ✅ Proper layering of platform vs application components
- ✅ Reasonable dependency chain depths
- ⚠️ One missing dependency to address

The only action item is to resolve the missing `openebs` dependency reference in the actions-runner-controller configuration.
