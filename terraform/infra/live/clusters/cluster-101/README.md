# Cluster-101 Deployment

Production Talos Linux Kubernetes cluster with BGP routing.

## Cluster Information

- **Name**: sol
- **ID**: 101
- **Control Planes**: 3 nodes
- **Workers**: 3 nodes
- **Network**: VNet 101 (SDN with BGP)
- **Talos Version**: Shared from `common/versions.hcl`

## Structure

```
cluster-101/
├── cluster.hcl        # Cluster definition (name, ID, nodes, network)
├── secrets/           # Talos cluster secrets (one-time)
├── compute/           # Proxmox VMs
├── config/            # Talos machine configs
├── apply/             # Apply configs to running cluster (no bootstrap)
└── bootstrap/         # Kubernetes bootstrap (one-time)
```

## Quick Start

### Initial Cluster Creation (One-Time)

```bash
# 1. Build shared artifacts (once for all clusters)
cd ../../artifacts
terragrunt run-all apply

# 2. Generate cluster secrets (one-time)
cd ../clusters/cluster-101/secrets
terragrunt apply

# 3. Create VMs
cd ../clusters/cluster-101/compute
terragrunt apply

# 4. Generate machine configs
cd ../config
terragrunt apply

# 5. Apply machine configs to running nodes
cd ../apply
terragrunt apply

# 6. Bootstrap cluster (includes Flux)
cd ../bootstrap
terragrunt apply
```

### Run-All (Full Stack)

```bash
# Full stack in dependency order
terragrunt apply --all
```

### Updating Running Cluster (Repeatable)

When you need to update machine configs (network, extensions, sysctls, etc.):

```bash
# 1. Regenerate machine configs with changes
cd config
terragrunt apply

# 2. Apply to running nodes (skips bootstrap)
cd ../apply
terragrunt apply
```

**Key**: Use `apply/` instead of `bootstrap/` to avoid re-bootstrapping an existing cluster.

## Deployment Stages

### Stage 0: Secrets (`secrets/`)

**Purpose**: Generate one-time Talos cluster secrets (CA, tokens, client certs)

**Actions**:
- Generates `talos_machine_secrets`
- Exports `secrets.sops.yaml` for reuse across rebuilds

**Destroy behavior**:
- Skipped by default on `terragrunt destroy`
- To destroy secrets intentionally: set `TALOS_DESTROY_SECRETS=1`

### Stage 1: Compute (`compute/`)

**Purpose**: Create Proxmox VMs for cluster nodes

**Dependencies**:
- Shared artifacts (`../../artifacts/registry/`) for boot ISO

**Actions**:
- Creates 6 VMs (3 control planes + 3 workers)
- Assigns IPv6/IPv4 addresses based on cluster ID
- Configures GPU passthrough for worker nodes
- Boots VMs from Talos ISO

**Outputs**:
- `node_ips`: Map of node names → IP addresses
- `talenv.yaml`: Environment file for Talos CLI

### Stage 2: Config (`config/`)

**Purpose**: Generate Talos machine configurations

**Dependencies**:
- Node IPs from `compute/`
- Installer image from `../../artifacts/images/`

**Actions**:
- Generates machine configs for all nodes
- Configures BGP with FRR extension
- Sets up dual-stack networking (IPv6 + IPv4)
- Configures control plane VIP (fd00:101::10)

**Outputs**:
- `talosconfig`: Talos CLI configuration
- Machine configs for troubleshooting

### Stage 3a: Apply (`apply/`) - For Updates

**Purpose**: Apply machine configs to running cluster

**Dependencies**:
- Machine configs from `config/`
- Running cluster with accessible Talos API

**Actions**:
- Applies updated machine configs to all nodes
- Changes take effect immediately (most don't require reboot)

**When to use**: Updating an existing cluster (network, extensions, sysctls)

### Stage 3b: Bootstrap (`bootstrap/`) - Initial Setup Only

**Purpose**: Bootstrap Kubernetes cluster (one-time)

**Dependencies**:
- Machine configs already applied via `apply/`

**Actions**:
- Bootstraps etcd on first control plane
- Installs Cilium CNI (BGP mode)
- Deploys Flux GitOps

**When to use**: Initial cluster creation only

**Safety**: Use `--terragrunt-exclude-dir bootstrap` to skip bootstrap in run-all

**Result**: Fully functional Kubernetes cluster

## Configuration

### Cluster Definition (`cluster.hcl`)

```hcl
locals {
  cluster_name   = "sol"      # Human-readable name
  cluster_id     = 101        # Numeric identifier (used for IP allocation)
  controlplanes  = 3          # Number of control plane nodes
  workers        = 3          # Number of worker nodes

  network = {
    bridge_mesh = "vnet101"   # SDN VNet for cluster
    use_sdn     = true        # Enable SDN with BGP
  }

  node_overrides = {
    # GPU passthrough configuration
    "solwk01" = { ... }
  }
}
```

**Network Design**:
- Public network: `fd00:101::/64` (IPv6), `10.0.101.0/24` (IPv4)
- Mesh network: `fc00:101::/64` (private inter-node)
- BGP peering: Unnumbered link-local to Proxmox SDN
- DNS: `fd00:101::ffff` (anycast gateway)

### IP Allocation

**Automatic IP assignment based on cluster ID:**

Control Planes:
- `solcp01`: fd00:101::11 / 10.0.101.11
- `solcp02`: fd00:101::12 / 10.0.101.12
- `solcp03`: fd00:101::13 / 10.0.101.13

Workers:
- `solwk01`: fd00:101::21 / 10.0.101.21
- `solwk02`: fd00:101::22 / 10.0.101.22
- `solwk03`: fd00:101::23 / 10.0.101.23

VIP (Control Plane):
- `fd00:101::10 / 10.0.101.10`

## Shared Artifacts

This cluster uses **shared artifacts** built at `../../artifacts/`:

- **Same Talos version** as all other clusters
- **Same extensions** (FRR, QEMU guest agent, etc.)
- **Version-based naming** (not cluster-specific)

**To upgrade Talos version**:
1. Update `common/versions.hcl`
2. Rebuild artifacts: `cd ../../artifacts && terragrunt run-all apply`
3. Redeploy cluster: `cd ../clusters/cluster-101 && terragrunt run-all apply`

## Troubleshooting

**Q: VMs not booting**
A: Verify ISO is uploaded to Proxmox: `cd ../../artifacts/registry && terragrunt output`

**Q: BGP not peering**
A: Check FRR logs: `talosctl logs -f -n fd00:101::11 frr`

**Q: Control plane VIP not reachable**
A: Verify VIP configuration: `talosctl get vips -n fd00:101::11`

**Q: Cilium not installing**
A: Check bootstrap logs: `talosctl -n fd00:101::11 dmesg -f`

## Related Documentation

- [Shared Artifacts](../../artifacts/README.md) - Image build pipeline
- [Multi-Cluster Refactoring](../../MULTI_CLUSTER_REFACTORING_PLAN.md) - Architecture
- [Common Versions](../../common/versions.hcl) - Centralized version management
