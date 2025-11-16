# Cluster Management Guide

This directory contains Terragrunt configurations for managing Kubernetes clusters on Proxmox.

## Directory Structure

```
live/
├── common/              # Shared configuration for all clusters
│   ├── credentials.hcl  # Proxmox credentials (SOPS encrypted)
│   ├── schematic.hcl    # Default Talos image schematic
│   └── versions.hcl     # Centralized version management
├── globals.hcl          # Global settings (uses common/versions.hcl)
└── cluster-<id>/        # Per-cluster configuration
    ├── cluster.hcl      # Cluster definition (nodes, network, etc.)
    ├── image.hcl        # Optional: override schematic for this cluster
    ├── image/           # Builds & uploads Talos image
    │   └── terragrunt.hcl
    └── nodes/           # Provisions VMs
        └── terragrunt.hcl
```

## Quick Start

### Create a New Cluster

```bash
# 1. Copy cluster template
cd terraform/infra/live
cp -r cluster-101 cluster-102

# 2. Update cluster configuration
cd cluster-102
```

Edit `cluster.hcl`:
```hcl
locals {
  cluster_name    = "102"  # Must match directory name
  cluster_id      = 102
  controlplanes   = 3
  workers         = 3
  proxmox_nodes   = ["pve01", "pve02", "pve03"]
  storage_default = "rbd-vm"

  network = {
    bridge_public = "vmbr0"
    vlan_public   = 102      # Update VLAN
    bridge_mesh   = "vnet102" # Update mesh bridge
    vlan_mesh     = 0
    public_mtu    = 1500
    mesh_mtu      = 8930
  }

  node_overrides = {
    # Optional: override specific node settings
    # "102-wk01" = { memory_mb = 32768 }
  }
}
```

### Deploy Cluster Infrastructure

```bash
# 3. Validate configuration
../../scripts/validate-cluster.sh 102

# 4. Create Talos secrets
task talos:gen-secrets -- 102

# 5. Build and upload Talos image
cd image
terragrunt apply

# 6. Provision VMs
cd ../nodes
terragrunt apply

# 7. Generate Talos machine configs
task talos:gen-config -- 102

# 8. Bootstrap cluster
task talos:bootstrap -- 102

# 9. Install CNI
task cni:bootstrap
```

## Configuration Files

### cluster.hcl

Defines the high-level cluster configuration:
- `cluster_name` - Cluster identifier (should match directory: cluster-ID)
- `cluster_id` - Numeric cluster ID (e.g., 101, 102)
- `controlplanes` - Number of control plane nodes
- `workers` - Number of worker nodes
- `proxmox_nodes` - List of Proxmox nodes to distribute VMs across
- `network` - Network configuration (VLANs, bridges, MTU)
- `node_overrides` - Per-node configuration overrides

### image.hcl (Optional)

Override the default Talos image schematic for this cluster only.

**Example:** Custom kernel args for specific hardware:
```hcl
locals {
  talos_extra_kernel_args = [
    "intel_iommu=on",
    "iommu=pt",
    "custom-arg=value"
  ]

  # Only include fields you want to override
  # Unspecified fields use defaults from common/schematic.hcl
}
```

Leave empty (or delete) to use defaults from `common/schematic.hcl`.

### common/versions.hcl

Centralized version management. Update versions here and all clusters inherit changes:

```hcl
locals {
  talos_version      = "v1.11.5"
  kubernetes_version = "v1.31.4"
  talos_platform     = "nocloud"
  talos_architecture = "amd64"
}
```

To override for a specific cluster, add to `cluster.hcl`:
```hcl
locals {
  # ... other settings
  talos_version = "v1.12.0"  # Override only for this cluster
}
```

### common/schematic.hcl

Default Talos image schematic applied to all clusters. Defines:
- Kernel arguments
- System extensions
- Talos patches

Override per-cluster using `image.hcl`.

## Node Naming Convention

Nodes are automatically named based on cluster ID and role:

**Control Planes:**
- `<cluster_id>cp01`, `<cluster_id>cp02`, `<cluster_id>cp03`
- Examples: `101cp01`, `102cp01`

**Workers:**
- `<cluster_id>wk01`, `<cluster_id>wk02`, `<cluster_id>wk03`
- Examples: `101wk01`, `102wk01`

## Network Configuration

### Dual-Stack Networking

Each cluster gets dual-stack (IPv4 + IPv6) networking:

**Public Network (ens18):**
- IPv4: `10.0.<cluster_id>.0/24`
- IPv6: `fd00:<cluster_id>::/64`
- Gateway: Configured in cluster.hcl

**Mesh Network (ens19):**
- IPv4: `10.10.<cluster_id>.0/24`
- IPv6: `fc00:<cluster_id>::/64`
- No gateway (internal only)

### VLAN Assignment

Recommended VLAN strategy:
- Cluster 101: VLAN 101
- Cluster 102: VLAN 102
- Cluster 103: VLAN 103

Configured in `cluster.hcl` under `network.vlan_public`.

## Resource Sizing

Default node sizing (defined in `nodes/terragrunt.hcl`):

**Control Plane Nodes:**
- CPU: 4 cores
- Memory: 8GB
- Disk: 40GB

**Worker Nodes:**
- CPU: 6 cores
- Memory: 16GB
- Disk: 80GB

Override per-node in `cluster.hcl`:
```hcl
locals {
  node_overrides = {
    "101-wk01" = {
      cpu_cores = 8
      memory_mb = 32768
      disk_gb   = 120
    }
  }
}
```

## Maintenance

### Update Talos Version

1. Update `common/versions.hcl`:
   ```hcl
   talos_version = "v1.12.0"
   ```

2. Rebuild images for all clusters:
   ```bash
   cd cluster-101/image && terragrunt apply
   cd ../../cluster-102/image && terragrunt apply
   ```

3. Update nodes following Talos upgrade procedure

### Update Cluster Configuration

After modifying `cluster.hcl` or network settings:

```bash
cd cluster-<id>/nodes
terragrunt apply
```

### Destroy Cluster

```bash
# ⚠️  WARNING: This destroys all VMs and data!
task cluster:destroy -- <cluster_id>
```

## Validation

Validate cluster configuration before applying:

```bash
# Validate specific cluster
./scripts/validate-cluster.sh 101

# Check all cluster statuses
./scripts/cluster-status.sh
```

## Troubleshooting

### Image Build Fails

Check:
- Proxmox node has sufficient disk space in `resources` datastore
- Network connectivity to Talos image factory
- Cache directory exists: `terraform/infra/cache/talos`

### VM Creation Fails

Check:
- Talos image uploaded successfully (`image/terragrunt.hcl` applied)
- Proxmox nodes specified in `cluster.hcl` exist and are accessible
- Storage pool `rbd-vm` exists and has capacity
- Network bridges/VLANs configured on Proxmox

### Node Configuration Mismatch

```bash
# Regenerate configs from Terraform state
task talos:gen-config -- <cluster_id>

# Validate consistency
./scripts/validate-cluster.sh <cluster_id>
```

## See Also

- [Talos Configuration Workflow](../../../talos/README.md)
- [Main Taskfile](../../../Taskfile.yml)
- [Cluster Status Script](../../../scripts/cluster-status.sh)
