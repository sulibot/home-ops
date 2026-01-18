# Flux Two-Phase Deployment

## Overview

This document describes the two-phase Flux deployment approach implemented to solve the `observedGeneration: -1` race condition during automated cluster bootstraps.

## Problem

The original `flux_bootstrap_git` approach deployed Flux controllers and sync resources simultaneously, causing a race condition:

1. Flux controllers deployed
2. GitRepository/Kustomization created immediately
3. HelmReleases created before helm-controller cache was ready
4. Result: 40+ HelmReleases stuck with `observedGeneration: -1`

## Solution: Two-Phase Deployment

### Phase 1: flux-operator (Controllers)
Deploy Flux controllers via Helm and wait for full readiness.

**Module:** `terraform/infra/modules/flux_operator`
**Terragrunt:** `terraform/infra/live/clusters/cluster-101/flux-operator`

**What it does:**
- Deploys flux-operator via Helm chart
- Waits for flux-operator deployment to be Available
- Waits for FluxInstance CRD to be established
- Only completes when operator is fully ready to accept FluxInstance resources

### Phase 2: flux-instance (Sync Configuration)
Create FluxInstance CR after operators are ready.

**Module:** `terraform/infra/modules/flux_instance`
**Terragrunt:** `terraform/infra/live/clusters/cluster-101/flux-instance`

**What it does:**
- Creates SOPS AGE secret for decryption
- Creates FluxInstance CR pointing to Git repository
- Waits for all Flux controllers (source, kustomize, helm, notification)
- Sleeps 45s for helm-controller cache initialization
- Runs post-bootstrap.sh for HelmRelease fixes and Kopia restore

## Deployment Order

```
compute → secrets → config → apply → bootstrap → flux-operator → flux-instance
```

### Detailed Flow

1. **bootstrap** - Talos cluster bootstrap, creates kubeconfig file
2. **flux-operator** - Deploys Flux operator, waits for CRD readiness
3. **flux-instance** - Creates sync resources AFTER controllers are ready

## Key Benefits

1. **Prevents race condition** - Controllers fully initialized before HelmReleases created
2. **Explicit ordering** - Terragrunt dependencies enforce correct sequence
3. **Better observability** - Clear separation between controller deployment and sync
4. **Consistent with onedr0p** - Similar pattern to popular reference implementation

## Configuration

### Versions

Configured in `terraform/infra/live/common/application-versions.hcl`:

```hcl
gitops = {
  flux_git_repository    = "https://github.com/sulibot/home-ops.git"
  flux_git_branch        = "main"
  flux_version           = "2.4.0"
  flux_operator_version  = "0.14.0"
}
```

### Dependencies

**flux-operator/terragrunt.hcl:**
```hcl
dependencies {
  paths = ["../bootstrap"]
}
```

**flux-instance/terragrunt.hcl:**
```hcl
dependencies {
  paths = ["../flux-operator"]
}
```

## Migration from flux_bootstrap_git

The old approach has been deprecated:

- `terraform/infra/modules/talos_bootstrap/flux.tf` - Removed flux_bootstrap_git resource
- `terraform/infra/modules/talos_bootstrap/providers.tf` - Removed Flux provider
- `terraform/infra/modules/talos_bootstrap/versions.tf` - Removed Flux provider requirement
- `terraform/infra/modules/talos_bootstrap/variables.tf` - Removed Flux variables
- `terraform/infra/modules/talos_bootstrap/main.tf` - Removed SOPS secret creation (moved to flux-instance)

## Deployment

### Full Cluster Bootstrap

```bash
cd terraform/infra/live/clusters/cluster-101
terragrunt run-all apply
```

This will apply in order:
1. compute (Proxmox VMs)
2. secrets (Talos machine secrets)
3. config (Talos machine configs)
4. apply (Apply configs to nodes)
5. bootstrap (Bootstrap Talos cluster)
6. flux-operator (Deploy Flux controllers)
7. flux-instance (Configure Flux sync)

### Individual Module Deployment

```bash
# Deploy just flux-operator
cd terraform/infra/live/clusters/cluster-101/flux-operator
terragrunt apply

# Deploy just flux-instance
cd terraform/infra/live/clusters/cluster-101/flux-instance
terragrunt apply
```

## Debugging

### Check flux-operator Status

```bash
kubectl get deployment flux-operator -n flux-system
kubectl get crd fluxinstances.fluxcd.controlplane.io
```

### Check FluxInstance

```bash
kubectl get fluxinstance -n flux-system
kubectl describe fluxinstance flux -n flux-system
```

### Check Flux Controllers

```bash
kubectl get deployments -n flux-system
kubectl get helmreleases -A | grep -v "True.*True"  # Find stuck releases
```

## Troubleshooting

### flux-operator times out during deployment

Check the operator logs:
```bash
kubectl logs -n flux-system deployment/flux-operator
```

### FluxInstance not creating controllers

Verify the FluxInstance CRD is established:
```bash
kubectl get crd fluxinstances.fluxcd.controlplane.io -o jsonpath='{.status.conditions[?(@.type=="Established")].status}'
```

### HelmReleases still stuck with observedGeneration: -1

This indicates helm-controller cache wasn't ready. The 45s sleep in flux-instance should prevent this, but if it persists:

1. Increase sleep time in `terraform/infra/modules/flux_instance/main.tf`
2. Check helm-controller logs: `kubectl logs -n flux-system deployment/helm-controller`
3. Manually trigger reconciliation: `flux reconcile helmrelease <name> -n <namespace>`

## References

- [flux-operator GitHub](https://github.com/controlplaneio-fluxcd/flux-operator)
- [FluxInstance API](https://github.com/controlplaneio-fluxcd/flux-operator/blob/main/docs/api/v1/flux-instance.md)
- [onedr0p/home-ops reference](https://github.com/onedr0p/home-ops/tree/main/bootstrap)
