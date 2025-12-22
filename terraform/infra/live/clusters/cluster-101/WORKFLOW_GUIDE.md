# Cluster Update Workflow Guide

This guide explains when and how to use each deployment step for cluster-101.

## Directory Purpose Summary

| Directory | Purpose | When to Use |
|-----------|---------|-------------|
| `compute/` | Create/update VMs | Initial deploy, VM config changes |
| `config/` | Generate machine configs | Always before apply/bootstrap |
| `apply/` | Update running cluster | Config updates on live cluster |
| `bootstrap/` | Bootstrap new cluster | **One-time only** at creation |

## Common Scenarios

### Scenario 1: Adding IPv6 ULA Addresses to Existing Nodes

**Problem**: Nodes only have GUA IPv6, need to add ULA

**Solution**:
```bash
# 1. Update machine config (already configured in talos_config module)
cd config
terragrunt apply

# 2. Apply to running nodes
cd ../apply
terragrunt apply

# 3. Verify
talosctl -n 10.0.101.11 get addresses
```

**Why not bootstrap?** Bootstrap would try to re-create the etcd cluster, which will fail.

---

### Scenario 2: Changing System Extensions

**Example**: Adding a new Talos extension

**Solution**:
```bash
# 1. Update common/install-schematic.hcl
vim ../../common/install-schematic.hcl

# 2. Rebuild artifacts (new boot ISO)
cd ../../artifacts
terragrunt run-all apply

# 3. Regenerate machine configs
cd ../clusters/cluster-101/config
terragrunt apply

# 4. Recreate VMs (extension in boot ISO)
cd ../compute
terragrunt apply

# 5. Bootstrap (cluster recreation)
cd ../bootstrap
terragrunt apply
```

**Why recreate?** Boot ISO contains extensions, VMs must boot from new ISO.

---

### Scenario 3: Updating Sysctls or Network Config

**Example**: Changing `net.ipv6.conf.all.forwarding`

**Solution**:
```bash
# 1. Update talos_config module
vim ../../../modules/talos_config/main.tf

# 2. Regenerate configs
cd config
terragrunt apply

# 3. Apply to running nodes
cd ../apply
terragrunt apply
```

**No VM recreation needed** - Talos applies sysctls live.

---

### Scenario 4: Kubernetes Version Upgrade

**Solution**:
```bash
# 1. Update version
vim ../../common/versions.hcl

# 2. Regenerate configs
cd config
terragrunt apply

# 3. Follow Talos upgrade guide
talosctl upgrade --nodes 10.0.101.11 --image ghcr.io/siderolabs/installer:v1.11.5
```

**Don't use Terraform** - Use `talosctl upgrade` for K8s upgrades.

---

### Scenario 5: Adding/Removing Nodes

**Solution**:
```bash
# 1. Update cluster.hcl
vim cluster.hcl  # Change controlplanes/workers count

# 2. Create new VMs
cd compute
terragrunt apply

# 3. Generate configs for new nodes
cd ../config
terragrunt apply

# 4. Apply configs to new nodes only
cd ../apply
terragrunt apply
```

**Note**: For removing nodes, use `talosctl reset` first, then destroy VMs.

---

## Decision Tree

```
Do you need to change...
│
├─ Boot ISO / Extensions?
│  └─> Rebuild artifacts → Recreate VMs → Bootstrap
│
├─ VM resources (CPU/RAM/Disk)?
│  └─> Update compute → Apply (VMs will be recreated)
│
├─ Machine config (network/sysctls)?
│  └─> Regenerate config → Apply to running cluster
│
├─ Kubernetes version?
│  └─> Use talosctl upgrade (not Terraform)
│
└─ GitOps/Flux manifests?
   └─> Just git commit (Flux auto-applies)
```

## Important Rules

### ✅ DO
- Use `apply/` for machine config updates
- Use `config/` before any apply/bootstrap
- Use `bootstrap/` only once at cluster creation
- Test changes in a separate cluster first

### ❌ DON'T
- Don't run `bootstrap/` on an existing cluster
- Don't skip `config/` regeneration
- Don't use Terraform for K8s version upgrades
- Don't modify running node configs manually

## Workflow Examples

### Example 1: Your Current Situation (Add ULA IPv6)

**Current State**: Nodes have GUA only (`2600:1700:ab1a:500e::11`)
**Goal**: Add ULA (`fd00:101::11`)

**Option A - Via Talos Config (Recommended)**:
```bash
cd config && terragrunt apply  # Config already has ULA
cd ../apply && terragrunt apply  # Apply to running nodes
```

**Option B - Via Cloud-init + VM Recreation**:
```bash
cd compute && terragrunt apply  # VMs recreated with custom cloud-init
```

**Recommendation**: Use Option A - no downtime, live config update.

---

### Example 2: Major Talos Version Upgrade

**Goal**: Upgrade from v1.11.5 to v1.12.0

```bash
# 1. Update versions
vim ../../common/versions.hcl

# 2. Rebuild artifacts
cd ../../artifacts && terragrunt run-all apply

# 3. Upgrade nodes one by one
talosctl upgrade --nodes 10.0.101.11 --image ghcr.io/sulibot/talos-frr-installer:v1.12.0
# Wait for node to come back...
talosctl upgrade --nodes 10.0.101.12 --image ghcr.io/sulibot/talos-frr-installer:v1.12.0
# ... repeat for all nodes
```

**Don't use Terraform** - Talos handles rolling upgrades safely.

## Summary

- **config/ + apply/**: Your main workflow for updates
- **bootstrap/**: Touch-once, forget forever
- **compute/**: Only when VMs need recreation
- **artifacts/**: Shared across all clusters, rebuild rarely
