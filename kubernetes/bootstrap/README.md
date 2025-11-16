# Bootstrap - Pre-Flux Component Installation

This directory contains configurations for installing critical components **before Flux is running**.

## The Chicken-and-Egg Problem

Flux itself needs networking to function, but Cilium (CNI) provides networking. Solution: Install Cilium manually first, then Flux adopts it.

## Components Installed

1. **Cilium CNI** - Container networking, kube-proxy replacement

## Prerequisites

- Talos cluster bootstrapped (API server running)
- `helmfile` installed on workstation
- `kubectl` configured to access cluster

## Installation

### Manual Installation (During Bootstrap)

```bash
# From repository root
cd kubernetes/bootstrap

# Install all components
helmfile apply

# Verify Cilium is running
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Automated Installation (via Taskfile)

```bash
# Part of cluster bootstrap
task talos:bootstrap -- 101
  # This automatically runs helmfile apply
```

## Post-Bootstrap: Flux Adoption

After installing Flux:

1. Flux sees the existing Cilium HelmRelease
2. Flux compares with Git configuration (`kubernetes/apps/kube-system/cilium/`)
3. Flux adopts management (no changes needed)
4. All future updates happen via Git

## Values Files

- `values/cilium.yaml` - Cilium configuration for cluster-101

These values are **identical** to those in `kubernetes/apps/kube-system/cilium/app/helmrelease.yaml`.

**Single source of truth**: If you update Cilium config, update BOTH files (or use symlinks).

## Troubleshooting

### Cilium pods not starting

```bash
# Check logs
kubectl logs -n kube-system -l k8s-app=cilium

# Common issue: wrong CIDRs
# Verify pod CIDR matches Talos config
talosctl get members
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'
```

### Flux not adopting Cilium

```bash
# Check HelmRelease
kubectl get helmrelease -n kube-system cilium

# Check if values match
helm get values cilium -n kube-system
# Compare with kubernetes/apps/kube-system/cilium/app/values.yaml
```

### Re-bootstrap

If you need to reinstall:

```bash
# Uninstall Cilium
helm uninstall cilium -n kube-system

# Wait for cleanup
kubectl delete pods -n kube-system -l k8s-app=cilium

# Re-run helmfile
helmfile apply
```

## Files

```
bootstrap/
├── helmfile.yaml          # Helm release definitions
├── values/
│   └── cilium.yaml        # Cilium values (cluster-101)
└── README.md              # This file
```

## Next Steps

After bootstrap:

1. ✅ Cilium installed
2. ✅ Cluster has networking
3. → Install Flux: `flux bootstrap github ...`
4. → Flux adopts Cilium
5. → All future changes via GitOps
