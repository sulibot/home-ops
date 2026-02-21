# Tier 0: Foundation

**Bootstrap Phase**: Sequential (wait: true)
**Purpose**: Critical infrastructure that must be ready before anything else deploys.

## Apps in this Tier

### CRDs (Custom Resource Definitions)
- **gateway-api-crds**: Gateway API CRDs required by Cilium
- **snapshot-controller-crds**: Volume snapshot CRDs

### CNI (Container Network Interface)
- **cilium**: Primary CNI - cluster won't function without networking

### Secrets Management
- **external-secrets**: Manages secrets from external providers (1Password)
- **onepassword**: 1Password Connect for secret injection

### Storage
- **ceph-csi**: Ceph CSI driver for persistent storage

## Bootstrap Behavior

- **Interval**: 30s (aggressive during bootstrap) → 15m (steady-state)
- **Wait**: `true` - Tier 1 won't start until all Tier 0 apps are Ready
- **Sequential**: Apps deploy in order defined in kustomization.yaml
- **Health Checks**: Ensures Cilium DaemonSet is running before proceeding

## Why These Apps?

These are the absolute foundations of the cluster:
1. **CRDs first**: Gateway API CRDs must exist before Cilium deploys
2. **Cilium second**: No networking = no pod communication
3. **Secrets third**: Most apps need secrets from 1Password
4. **Storage fourth**: Apps need persistent volumes

Without these, nothing else can function.
