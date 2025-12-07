# Terraform-based Talos Kubernetes Cluster (Clusters 101–103)

This repository uses **Terraform/Terragrunt** to build Kubernetes clusters end-to-end with **Taskfile** orchestration.

**Pipeline:** build custom Talos image → provision VMs (Proxmox) → generate Talos configs → bootstrap cluster (Cilium + Flux)

> ⚠️ All secrets in `common/secrets.sops.yaml` must be encrypted with SOPS before use.

## Quick Start

```bash
# List all available tasks
task --list

# Create complete cluster (one command)
task cluster:create CLUSTER_ID=101

# Show what will be created
task cluster:plan CLUSTER_ID=101

# Check cluster status
task cluster:status CLUSTER_ID=101

# Destroy cluster
task cluster:destroy CLUSTER_ID=101

## Directory Structure

The `infra/` directory contains a Terragrunt-based layout:

```
infra/
├── modules/
│   ├── talos_image_factory/  # Builds custom Talos images
│   ├── cluster_core/          # Provisions VMs on Proxmox
│   ├── talos_config/          # Generates Talos machine configs
│   └── talos_bootstrap/       # Bootstraps cluster (Cilium + Flux)
├── live/
│   ├── common/
│   │   ├── credentials.hcl    # Proxmox credentials (SOPS encrypted)
│   │   ├── versions.hcl       # Centralized version management
│   │   ├── schematic.hcl      # Talos image customization
│   │   └── secrets.sops.yaml  # SOPS-encrypted secrets
│   └── cluster-101/
│       ├── image/             # Talos image stack
│       ├── nodes/             # VM provisioning stack
│       ├── talos-config/      # Talos configuration stack
│       ├── bootstrap/         # Cluster bootstrap stack
│       ├── cluster.hcl        # Cluster-specific configuration
│       └── image.hcl          # Optional: override schematic
└── root.hcl                   # Root Terragrunt configuration
```

## Manual Workflow (without Task)

If you prefer to run Terragrunt directly:

```bash
# 1. Build/upload the Talos image
cd terraform/infra/live/cluster-101/image
terragrunt apply

# 2. Provision VMs
cd ../nodes
terragrunt apply

# 3. Generate Talos configurations
cd ../talos-config
terragrunt apply

# 4. Bootstrap cluster with Cilium and Flux
cd ../bootstrap
terragrunt apply
```

## Available Tasks

### Cluster Lifecycle
- `task cluster:create CLUSTER_ID=101` - Create complete cluster (image → nodes → talos-config → bootstrap)
- `task cluster:destroy CLUSTER_ID=101` - Destroy cluster (reverse order)
- `task cluster:plan CLUSTER_ID=101` - Show Terraform plan for all stacks
- `task cluster:reset CLUSTER_ID=101` - Reset and recreate cluster (keeps image)

### Individual Stacks
- `task cluster:image:apply CLUSTER_ID=101` - Build/upload Talos image
- `task cluster:nodes:apply CLUSTER_ID=101` - Provision VMs
- `task cluster:talos-config:apply CLUSTER_ID=101` - Generate Talos configs
- `task cluster:bootstrap:apply CLUSTER_ID=101` - Bootstrap cluster

### Status and Monitoring
- `task cluster:status CLUSTER_ID=101` - Show cluster status
- `task cluster:health CLUSTER_ID=101` - Check cluster health
- `task cluster:kubeconfig CLUSTER_ID=101` - Export kubeconfig path
- `task cluster:talosconfig CLUSTER_ID=101` - Export talosconfig path

### Maintenance
- `task cluster:init CLUSTER_ID=101` - Initialize all Terragrunt stacks
- `task cluster:clean CLUSTER_ID=101` - Clean Terraform cache files
- `task cluster:upgrade CLUSTER_ID=101` - Upgrade cluster versions

## Version Management

All versions are centrally managed in `infra/live/common/versions.hcl`:

```hcl
locals {
  # Talos and Kubernetes versions
  talos_version      = "v1.11.5"
  kubernetes_version = "v1.31.4"

  # Terraform provider versions
  provider_versions = {
    talos      = "~> 0.9.0"
    proxmox    = "~> 0.89.0"
    helm       = "~> 3.1.1"
    kubernetes = "~> 3.0.0"
    kubectl    = "~> 1.14.0"
  }

  # Application versions
  cilium_version = "1.18.4"
  flux_version   = "latest"
}
```

To upgrade versions:
1. Update `versions.hcl`
2. Run `task cluster:upgrade CLUSTER_ID=101`

## Customization

### Talos Image Extensions

Modify `infra/live/common/schematic.hcl` to add kernel arguments or system extensions:

```hcl
locals {
  schematic = {
    kernel_args = [
      "intel_iommu=on",
      "module_blacklist=igc",
    ]
    system_extensions = {
      official = [
        "siderolabs/i915",
        "siderolabs/zfs",
      ]
      custom = [{
        image = "ghcr.io/example/custom-extension:v1.0.0"
      }]
    }
  }
}
```

### Per-Cluster Overrides

Override settings in `cluster-101/cluster.hcl`:

```hcl
locals {
  cluster_name  = "sol"
  cluster_id    = 101
  controlplanes = 3
  workers       = 3

  # Override specific node resources
  node_overrides = {
    "sol-wk01" = {
      memory_mb = 32768
      cpu_cores = 8
    }
  }
}
```

## Secrets Management

Secrets are managed with SOPS. Ensure you have SOPS configured with your encryption key.

Create `infra/live/common/secrets.sops.yaml`:
```yaml
pve_endpoint: https://pve01.example.com:8006
pve_api_token_id: terraform@pam!token
pve_api_token_secret: your-secret-here
```

Encrypt with:
```bash
sops -e -i infra/live/common/secrets.sops.yaml
```

## Outputs

After successful cluster creation:
- **Talosconfig**: `talos/clusters/cluster-101/talosconfig`
- **Kubeconfig**: `talos/clusters/cluster-101/kubeconfig`

Set environment variables:
```bash
export TALOSCONFIG=$(task cluster:talosconfig CLUSTER_ID=101)
export KUBECONFIG=$(task cluster:kubeconfig CLUSTER_ID=101)
```

## Troubleshooting

### Check individual stack status
```bash
cd terraform/infra/live/cluster-101/bootstrap
terragrunt state list
terragrunt output
```

### Re-run specific stack
```bash
task cluster:bootstrap:apply CLUSTER_ID=101
```

### Clean and reinitialize
```bash
task cluster:clean CLUSTER_ID=101
task cluster:init CLUSTER_ID=101
```

## GitHub Actions
- CI runs `terraform fmt/validate/plan` on PRs
- Manual `workflow_dispatch` can trigger cluster creation (requires secrets configuration)
