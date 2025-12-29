# Multi-Cluster Infrastructure

Enterprise-grade multi-cluster management for Talos Linux Kubernetes on Proxmox.

## Architecture Overview

This infrastructure follows **Option A: Environment-Based Structure** with shared artifacts:

```
live/
├── common/              # Shared configuration
│   ├── versions.hcl            # Centralized version management
│   ├── install-schematic.hcl   # System extensions
│   ├── ipv6-prefixes.hcl       # IPv6 GUA allocation
│   ├── 0-sdn-setup/            # Proxmox SDN configuration
│   └── 1-firewall/             # Proxmox firewall rules
│
├── artifacts/           # Shared artifact pipeline (NEW)
│   ├── extension/      # Build FRR extension (optional)
│   ├── images/         # Build installer + ISO
│   └── registry/       # Upload ISO to Proxmox
│
└── clusters/            # Multi-cluster deployments (NEW)
    ├── cluster-101/    # Production (sol)
    ├── cluster-102/    # Staging (luna)
    └── cluster-103/    # Development (terra)
```

### Key Principles

1. **Shared Artifacts**: Build Talos images once, deploy to multiple clusters
2. **Version Consistency**: All clusters use the same Talos version from `common/versions.hcl`
3. **DRY (Don't Repeat Yourself)**: No duplication of image build logic
4. **Clear Separation**: Artifact generation vs cluster deployment

## Quick Start

### Deploy a New Cluster

**Step 1: Build Shared Artifacts (Run Once)**

```bash
cd artifacts
terragrunt run-all apply
```

This builds:
- Installer image: `ghcr.io/sulibot/talos-frr-installer:v1.11.5`
- Boot ISO: `talos-frr-v1.11.5-nocloud-amd64.iso`
- Uploads ISO to all Proxmox nodes

**Step 2: Deploy Cluster**

```bash
cd clusters/cluster-101
terragrunt run-all apply
```

This executes:
1. `compute/` - Creates Proxmox VMs
2. `config/` - Generates Talos machine configs
3. `bootstrap/` - Bootstraps Kubernetes cluster

### Add a New Cluster

```bash
# 1. Copy existing cluster
cd clusters
cp -r cluster-101 cluster-102

# 2. Update cluster.hcl
cd cluster-102
vim cluster.hcl
```

Edit these fields:
```hcl
locals {
  cluster_name = "luna"  # Change from "sol"
  cluster_id   = 102     # Change from 101

  network = {
    vlan_public = 102    # Change from 101
    bridge_mesh = "vnet102"  # Change from "vnet101"
  }
}
```

```bash
# 3. Deploy (uses shared artifacts automatically)
terragrunt run-all apply
```

**That's it!** No need to rebuild images - cluster-102 uses the same artifacts as cluster-101.

## Directory Structure

### `common/` - Shared Configuration

**Purpose**: Configuration shared across all clusters

**Files**:
- `versions.hcl` - Talos version, Kubernetes version
- `install-schematic.hcl` - System extensions (FRR, QEMU, etc.)
- `ipv6-prefixes.hcl` - IPv6 GUA prefix delegation
- `credentials.hcl` - Proxmox credentials (SOPS encrypted)
- `0-sdn-setup/` - Proxmox SDN VNets (vnet100-103)
- `1-firewall/` - Proxmox firewall rules

**When to modify**:
- Upgrading Talos/Kubernetes for all clusters
- Adding/removing system extensions
- Changing IPv6 prefix allocation

### `artifacts/` - Shared Artifact Pipeline

**Purpose**: Build Talos images once, consumed by all clusters

**Stages**:
1. `extension/` - Build custom FRR extension (optional)
2. `images/` - Build installer (metal) + ISO (nocloud)
3. `registry/` - Upload ISO to Proxmox Ceph storage

**Outputs**:
- Installer: `ghcr.io/sulibot/talos-frr-installer:v1.11.5`
- ISO: `talos-frr-v1.11.5-nocloud-amd64.iso`

**When to rebuild**:
- After updating `common/versions.hcl`
- After changing system extensions
- When adding new extension versions

See [artifacts/README.md](artifacts/README.md) for details.

### `clusters/` - Multi-Cluster Deployments

**Purpose**: Per-cluster deployment configurations

**Each cluster contains**:
- `cluster.hcl` - Cluster definition (name, ID, nodes, network)
- `compute/` - Proxmox VM creation
- `config/` - Talos machine configuration generation
- `bootstrap/` - Kubernetes cluster bootstrap

**Cluster Naming**:
- cluster-101: Production (sol)
- cluster-102: Staging (luna)
- cluster-103: Development (terra)

**IP Allocation** (automatic based on cluster_id):
- Public IPv6: `fd00:${cluster_id}::/64`
- Public IPv4: `10.${cluster_id}.0.0/24`
- Control plane VIP: `fd00:${cluster_id}::10`

## Workflow

### Initial Setup (Once)

```bash
# 1. Configure Proxmox SDN
cd common/0-sdn-setup
terragrunt apply

# 2. Configure Proxmox firewall
cd ../1-firewall
terragrunt apply

# 3. Build shared artifacts
cd ../../artifacts
terragrunt run-all apply
```

### Deploy Cluster-101 (Production)

```bash
cd clusters/cluster-101

# Run complete pipeline
terragrunt run-all apply

# Or run stages separately:
cd compute && terragrunt apply    # Create VMs
cd ../config && terragrunt apply  # Generate configs
cd ../bootstrap && terragrunt apply  # Bootstrap K8s
```

### Deploy Cluster-102 (Staging)

```bash
# Copy cluster-101
cp -r clusters/cluster-101 clusters/cluster-102

# Edit cluster.hcl (change cluster_name, cluster_id, network)
vim clusters/cluster-102/cluster.hcl

# Deploy (uses shared artifacts automatically)
cd clusters/cluster-102
terragrunt run-all apply
```

### Upgrade Talos Version

**For all clusters**:

```bash
# 1. Update version
vim common/versions.hcl
# Change: talos_version = "v1.12.0"

# 2. Rebuild shared artifacts
cd artifacts
terragrunt run-all apply

# 3. Upgrade each cluster
cd ../clusters/cluster-101
terragrunt run-all apply

cd ../cluster-102
terragrunt run-all apply
```

This ensures all clusters stay on the same version.

## Configuration Reference

### `common/versions.hcl`

Centralized version management for all clusters:

```hcl
locals {
  talos_version      = "v1.11.5"      # Talos Linux version
  kubernetes_version = "1.31.4"       # Kubernetes version
  talos_platform     = "nocloud"      # Platform for boot ISO
  talos_architecture = "amd64"        # CPU architecture
  cilium_version     = "1.18.4"       # Cilium CNI version
}
```

### `common/install-schematic.hcl`

System extensions included in all images:

```hcl
locals {
  install_system_extensions = [
    "ghcr.io/siderolabs/intel-ucode:20250812@sha256:...",
    "ghcr.io/siderolabs/qemu-guest-agent:10.0.2@sha256:...",
    "ghcr.io/siderolabs/crun:1.24@sha256:...",
    "ghcr.io/siderolabs/ctr:v2.1.5@sha256:...",
  ]

  install_custom_extensions = [
    "ghcr.io/sulibot/talos-frr-extension:v1.0.18",
  ]

  install_kernel_args = [
    "talos.unified_cgroup_hierarchy=1",
  ]
}
```

### `cluster.hcl` (per cluster)

Cluster-specific configuration:

```hcl
locals {
  cluster_name   = "sol"              # Human-readable name
  cluster_id     = 101                # Numeric ID (affects IPs)
  controlplanes  = 3                  # Control plane count
  workers        = 3                  # Worker count
  proxmox_nodes  = ["pve01", "pve02", "pve03"]
  proxmox_hostnames = ["pve01.sulibot.com", ...]

  network = {
    bridge_public = "vmbr0"           # Physical bridge
    vlan_public   = 101               # VLAN ID
    bridge_mesh   = "vnet101"         # SDN VNet
    use_sdn       = true              # Enable SDN with BGP
  }

  node_overrides = {
    # Per-node customization (GPU, sizing, etc.)
    "solwk01" = {
      gpu_passthrough = { ... }
    }
  }
}
```

## Network Design

### Cluster Isolation

Each cluster gets isolated networks based on `cluster_id`:

**Cluster-101**:
- Public: `fd00:101::/64`, `10.0.101.0/24`
- VIP: `fd00:101::10`
- VNet: `vnet101`
- BGP ASN: `421010101X` (X = node suffix)

**Cluster-102**:
- Public: `fd00:102::/64`, `10.0.102.0/24`
- VIP: `fd00:102::10`
- VNet: `vnet102`
- BGP ASN: `421010201X`

### BGP Routing

- **Protocol**: Unnumbered BGP over link-local IPv6
- **Peer**: Proxmox SDN anycast gateway (`fe80::255:ffff`)
- **Advertised**: Node loopback IPs (`fd00:255:${cluster_id}::${node_suffix}`)
- **Learned**: Default route (`::/0`, `0.0.0.0/0`)

## Dependency Graph

```
common/versions.hcl ──┐
common/install-schematic.hcl ──┼──> artifacts/images/ ──> artifacts/registry/
                                │
                                └──> clusters/cluster-101/config/
                                     clusters/cluster-101/compute/ ──┘

artifacts/registry/ ───> clusters/cluster-101/compute/
artifacts/images/ ─────> clusters/cluster-101/config/
```

**Terragrunt automatically resolves these dependencies** - just run `terragrunt run-all apply`.

## Best Practices

### 1. Build Artifacts First

Always build shared artifacts before deploying clusters:

```bash
cd artifacts && terragrunt run-all apply
cd clusters/cluster-101 && terragrunt run-all apply
```

### 2. Version Consistency

Keep all clusters on the same Talos version:
- Update `common/versions.hcl`
- Rebuild `artifacts/`
- Upgrade all clusters

### 3. Use `run-all` for Pipelines

Let Terragrunt handle dependency order:

```bash
terragrunt run-all apply  # Correct order automatically
```

### 4. Test in Staging First

Use cluster-102 (staging) to test changes before production:

```bash
# Test in staging
cd clusters/cluster-102 && terragrunt run-all apply

# Validate
kubectl --context luna get nodes

# Deploy to production
cd ../cluster-101 && terragrunt run-all apply
```

### 5. Document Cluster Purpose

Update cluster README with:
- Cluster purpose (prod/staging/dev)
- Special configuration
- Ownership/contacts

## Troubleshooting

### Artifacts Not Building

```bash
cd artifacts/images
terragrunt plan  # Check for errors
terragrunt apply --terragrunt-log-level debug
```

### Cluster Can't Find ISO

```bash
# Verify ISO uploaded
cd artifacts/registry
terragrunt output

# Should show:
# talos_image_file_ids = {
#   "pve01" = "resources:iso/talos-frr-v1.11.5-nocloud-amd64.iso"
# }
```

### Dependency Resolution Fails

```bash
# Clear cache
rm -rf .terragrunt-cache

# Re-init
terragrunt run-all init
terragrunt run-all plan
```

### Version Mismatch

```bash
# Check versions
cat common/versions.hcl
cd artifacts/images && terragrunt output talos_version
cd clusters/cluster-101/compute && terragrunt output talos_version

# Should all match
```

## Migration from Old Structure

**Old (Per-Cluster Artifacts)**:
```
cluster-101/
├── artifacts/build/
├── artifacts/publish/
└── cluster/...
```

**New (Shared Artifacts)**:
```
artifacts/images/
artifacts/registry/
clusters/cluster-101/...
```

**Migration completed**: All paths updated, no per-cluster artifact duplication.

## Related Documentation

- [Shared Artifacts Pipeline](artifacts/README.md) - Detailed artifact build documentation
- [Cluster-101 Deployment](clusters/cluster-101/README.md) - Production cluster example
- [Multi-Cluster Refactoring Plan](MULTI_CLUSTER_REFACTORING_PLAN.md) - Architecture decisions

## Success Criteria

✅ Artifacts built once, consumed by all clusters
✅ Adding cluster-102 requires only `cluster.hcl` + deployment files
✅ No duplication of image build logic
✅ Clear naming: `artifacts/` vs `clusters/`
✅ Version consistency enforced automatically
