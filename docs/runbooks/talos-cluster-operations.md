# Talos Cluster Operations Runbook

## Table of Contents
1. [Configuration Stages](#configuration-stages)
2. [Common Operations](#common-operations)
3. [Decision Trees](#decision-trees)
4. [Troubleshooting](#troubleshooting)
5. [Emergency Procedures](#emergency-procedures)
6. [Verification Checklists](#verification-checklists)

---

## Configuration Stages

### Overview: Four-Stage Workflow

```
secrets → compute → config → apply/patch/bootstrap
```

### Stage 1: Secrets (One-time)
**Directory**: `terraform/infra/live/clusters/cluster-101/secrets/`

**Purpose**: Generate Talos cluster secrets (certificates, keys, tokens)

**When to run**:
- Initial cluster setup
- Rotating cluster secrets (rare)

**Command**:
```bash
cd terraform/infra/live/clusters/cluster-101/secrets
terragrunt apply
```

**Outputs**: `talosconfig`, `machine_secrets`, `client_configuration`

---

### Stage 2: Compute (Infrastructure)
**Directory**: `terraform/infra/live/clusters/cluster-101/compute/`

**Purpose**: Create VM infrastructure (Proxmox VMs)

**When to run**:
- Initial cluster setup
- Adding/removing nodes
- Changing VM resources (CPU, RAM, disk)

**Command**:
```bash
cd terraform/infra/live/clusters/cluster-101/compute
terragrunt apply
```

**Outputs**: VM IDs, IP addresses

---

### Stage 3: Config (Configuration Generation)
**Directory**: `terraform/infra/live/clusters/cluster-101/config/`

**Purpose**: Generate Talos machine configurations (base + patches)

**When to run**:
- After any change to node configuration
- Before applying via `apply/` or `patch/` stages

**Command**:
```bash
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
```

**Outputs**:
- `machine_configs` - Base config + per-node patches
- `talosconfig` - CLI configuration file
- `all_node_ips` - Node IP addresses

**What gets generated**:
- Base machine configuration (sysctls, Cilium, inline manifests)
- Per-node patches (hostname, IPs, FRR config, labels)

---

### Stage 3a: Apply (Full Base + Patch)
**Directory**: `terraform/infra/live/clusters/cluster-101/apply/`

**Purpose**: Apply full machine configuration (base + patch) to nodes

**When to run**:
- ⚠️ **Initial cluster bootstrap** (first time only)
- ⚠️ **Base config changes**: Cilium version, cluster-wide sysctls, inline manifests
- ⚠️ **Templated cluster standards**: MTU, DNS servers, route patterns, VLAN config

**Command**:
```bash
cd terraform/infra/live/clusters/cluster-101/apply
terragrunt apply
```

**⚠️ WARNING**: Re-applies base config. Can cause temporary issues if not careful. Test on single node first.

**Use cases**:
- Bootstrap new cluster
- Update Cilium version (inline manifest in base)
- Change cluster-wide sysctls in base config
- Change MTU cluster-wide (templated standard in patch)
- Change DNS servers cluster-wide (templated standard in patch)
- Update VLAN configuration (templated role-wide standard)

---

### Stage 3b: Patch (Patch-Only, Recommended)
**Directory**: `terraform/infra/live/clusters/cluster-101/patch/`

**Purpose**: Apply ONLY per-node patches without touching base config

**When to run**:
- ✅ **Routine updates** (safe, recommended)
- ✅ **Node labels**: Topology, BGP ASN, GPU tags
- ✅ **Per-node FRR config**: BGP peers, route filters
- ✅ **Per-node network changes**: Single node's IP, routes
- ✅ **Per-node sysctls**: Override for specific nodes

**Command**:
```bash
cd terraform/infra/live/clusters/cluster-101/patch
terragrunt apply
```

**✅ SAFE**: Only patches are applied. Hostname, IPs, and routing preserved.

**How it works**:
1. Terragrunt hooks generate patch files from `config/` outputs
2. `talosctl patch machineconfig` applies patches to running nodes
3. No base config re-application
4. Strategic merge: patch values override base values

**Patch structure**:
The `config_patch` contains TWO YAML documents:
1. Machine config patch (nodeLabels, network, kubelet, kernel)
2. ExtensionServiceConfig patch (FRR BGP configuration)

Both update safely via this stage.

---

## Common Operations

### 1. Update Node Labels

**Scenario**: Add GPU label to worker node

**Steps**:
```bash
# 1. Edit config module
vim terraform/infra/modules/talos_config/main.tf
# Add label to nodeLabels section (lines 808-825)

# 2. Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# 3. Apply patch (safe)
cd ../patch
terragrunt apply

# 4. Verify
kubectl get nodes --show-labels | grep gpu
```

**Stage used**: `patch/` ✅

---

### 2. Change FRR BGP Configuration

**Scenario**: Update BGP peers or route filters

**Steps**:
```bash
# 1. Edit FRR config in talos_config module
vim terraform/infra/modules/talos_config/main.tf
# Modify frr_config_yamls local (lines 375-780)

# 2. Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# 3. Apply patch (FRR config is in ExtensionServiceConfig patch)
cd ../patch
terragrunt apply

# 4. Verify BGP sessions
kubectl exec -n kube-system ds/cilium -- cilium bgp peers
```

**Stage used**: `patch/` ✅

**Note**: FRR configuration is part of the ExtensionServiceConfig document in config_patch, so it updates via patch stage.

---

### 3. Update Cilium Version

**Scenario**: Upgrade Cilium CNI

**Steps**:
```bash
# 1. Edit Cilium version
vim terraform/infra/modules/talos_config/variables.tf
# Update cilium_version default value

# 2. Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# 3. Apply to nodes (base config change)
cd ../apply
terragrunt apply  # Re-applies base + patch

# 4. Verify Cilium pods restart
kubectl get pods -n kube-system -w
kubectl exec -n kube-system ds/cilium -- cilium version
```

**Stage used**: `apply/` ⚠️ (Cilium is inline manifest in base config)

**Risk**: Base config re-application. Test on single node first.

---

### 4. Change Sysctls

#### Option A: Add/Override Sysctls (Per-Node or Cluster-Wide)

**Add to patch for per-node override**:
```bash
# 1. Edit patch section
vim terraform/infra/modules/talos_config/main.tf
# Add to machine.sysctls in config_patch (lines 804-940)

machine = merge(
  {
    sysctls = {
      "net.core.somaxconn" = "65535"  # New sysctl
    }
  }
)

# 2. Regenerate and apply patch
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
cd ../patch
terragrunt apply
```

**Stage used**: `patch/` ✅

**Add to base for cluster-wide defaults**:
```bash
# 1. Edit base sysctls
vim terraform/infra/modules/talos_config/main.tf
# Add to local.common_sysctls (around line 254)

# 2. Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# 3. Apply to nodes (base config change)
cd ../apply
terragrunt apply
```

**Stage used**: `apply/` ⚠️ (Base config change)

#### Option B: Remove Sysctl from Base

**Steps**:
```bash
# 1. Remove from base config
vim terraform/infra/modules/talos_config/main.tf
# Remove from local.common_sysctls

# 2. Regenerate and apply
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
cd ../apply
terragrunt apply  # Must use apply to remove from base
```

**Stage used**: `apply/` ⚠️ (Patches can't remove, only add/override)

---

### 5. Change MTU Cluster-Wide

**Scenario**: Update MTU from 1450 to 1500 for all nodes

**Steps**:
```bash
# 1. Edit MTU in patch template
vim terraform/infra/modules/talos_config/main.tf
# Change mtu = 1450 to mtu = 1500 (line ~831)

# 2. Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# 3. Apply to nodes (templated cluster standard change)
cd ../apply
terragrunt apply  # Re-applies base + new patch template

# 4. Verify MTU on nodes
talosctl -n solwk01 get links | grep -i mtu
```

**Stage used**: `apply/` ⚠️ (Templated cluster standard)

**Why apply/ not patch/**:
- MTU is in patch config but is a "templated cluster standard"
- Changing it requires re-templating for ALL nodes
- Use apply/ to sync the new template to all nodes

---

### 6. Change DNS Servers Cluster-Wide

**Scenario**: Update cluster DNS servers

**Steps**:
```bash
# 1. Edit DNS servers variable
vim terraform/infra/modules/talos_config/variables.tf
# Update dns_servers default value

# 2. Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# 3. Apply to nodes (templated cluster standard)
cd ../apply
terragrunt apply

# 4. Verify DNS on nodes
talosctl -n solwk01 get resolvers
```

**Stage used**: `apply/` ⚠️ (Templated cluster standard)

---

### 7. Change Single Node's IP Address

**Scenario**: Update one node's IP address

**Steps**:
```bash
# 1. Edit node IP in variables
vim terraform/infra/live/clusters/cluster-101/compute/terragrunt.hcl
# Update that node's public_ipv4/ipv6

# 2. Regenerate configs
cd ../config
terragrunt apply

# 3. Apply patch to that node only
cd ../patch
terragrunt apply  # Safe - only patches

# 4. Verify
kubectl get nodes -o wide
```

**Stage used**: `patch/` ✅ (Truly per-node)

---

## Decision Trees

### "Which Stage Do I Use?" Flowchart

```
┌─────────────────────────────────────┐
│ What are you changing?              │
└─────────────────────────────────────┘
                 │
         ┌───────┴───────┐
         │               │
    ┌────▼────┐    ┌────▼────┐
    │ Base    │    │ Patch   │
    │ Config? │    │ Config? │
    └────┬────┘    └────┬────┘
         │               │
         │         ┌─────┴─────────────┐
         │         │                   │
         │    ┌────▼────┐        ┌────▼────┐
         │    │Templated│        │ Truly   │
         │    │Cluster  │        │Per-Node?│
         │    │Standard?│        └────┬────┘
         │    └────┬────┘             │
         │         │                  │
    ┌────▼─────────▼────┐        ┌───▼────┐
    │ Use apply/ stage  │        │  Use   │
    │ ⚠️ Test on 1 node │        │ patch/ │
    │    first          │        │ stage  │
    └───────────────────┘        │   ✅   │
                                 └────────┘
```

### "Can This Be Patched?" Decision Tree

**Question**: Does this change require re-templating for ALL nodes?

**Examples**:

| Change | All Nodes? | Stage |
|--------|-----------|-------|
| Cilium version | YES | `apply/` |
| MTU cluster-wide | YES | `apply/` |
| DNS servers | YES | `apply/` |
| Base sysctl | YES | `apply/` |
| VLAN IDs (workers) | YES | `apply/` |
| Node label (one node) | NO | `patch/` |
| Node IP (one node) | NO | `patch/` |
| FRR config (per-node) | NO | `patch/` |
| Sysctl override (one node) | NO | `patch/` |

---

### Base Config vs Patch Determination

**Base Config Contains**:
- Cluster identity (certs, secrets, API server, etcd)
- CNI choice (name = "none", Cilium via inline manifests)
- Pod/Service CIDRs
- Cluster-wide sysctls (kernel parameters for all nodes)
- Cluster-wide features (hostDNS, kubePrism, etc.)
- Inline manifests (Gateway API CRDs, Cilium Helm chart, BGP configs)

**Patch Config Contains**:

**1. Truly Per-Node** (different per node):
- Hostname
- IP addresses
- Loopback addresses
- Node-specific labels (GPU, USB)
- Per-node BGP ASN
- VIP (controlplane only)
- GPU kernel modules (conditional)

**2. Templated Cluster Standards** (same pattern for all, but in patch):
- MTU (cluster-wide VXLAN overhead standard)
- DNS nameservers (cluster-wide)
- Default route patterns (cluster gateway configuration)
- VLAN configuration (role-wide: all workers same)
- Region topology label (cluster-wide)

**Why templated standards are in patch**:
- Talos base config is for cluster-wide, **node-agnostic** settings
- Network configuration is inherently **node-specific** in Talos
- Even if templated the same, it must be in patches
- This is correct Talos architecture, not a drift problem

---

## Troubleshooting

### Problem 1: Node Lost Hostname/IPs After Config Apply

**Symptoms**:
```bash
kubectl get nodes
# Node shows wrong hostname or IP

talosctl -n <node-ip> get members
# Hostname changed unexpectedly
```

**Root Cause**: Used `apply/` stage when `patch/` stage should have been used

**Solution**:
```bash
# 1. Check what was applied
cd terraform/infra/live/clusters/cluster-101/apply
terragrunt show

# 2. Regenerate correct configs
cd ../config
terragrunt apply

# 3. Re-apply with correct stage
cd ../apply
terragrunt apply  # This will fix hostname/IPs

# 4. Verify node identity restored
kubectl get nodes -o wide
talosctl get members
```

**Prevention**: Always use `patch/` for routine updates

---

### Problem 2: BGP Sessions Not Establishing

**Symptoms**:
```bash
kubectl exec -n kube-system ds/cilium -- cilium bgp peers
# Shows "not established" or missing peers
```

**Debug Steps**:
```bash
# 1. Check FRR is running
talosctl -n solwk01 services
# Look for ext-frr service

# 2. Check FRR logs
talosctl -n solwk01 logs ext-frr

# 3. Check FRR config was applied
talosctl -n solwk01 read /usr/local/etc/frr/config.yaml

# 4. Check BGP neighbors in FRR
talosctl -n solwk01 shell
vtysh -c 'show bgp summary'
vtysh -c 'show bgp neighbors'

# 5. Check Cilium BGP config
kubectl get ciliumbgppeeringpolicies -o yaml
kubectl get ciliumbgpnodeconfigs -o yaml
```

**Common Causes**:
- FRR config not updated (use `patch/` stage)
- Wrong ASN in FRR config
- Firewall blocking port 179
- Cilium not configured for BGP peering

**Solution**:
```bash
# Update FRR config via patch
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
cd ../patch
terragrunt apply

# Verify FRR restarted
talosctl -n solwk01 services ext-frr
```

---

### Problem 3: FRR Extension Not Running

**Symptoms**:
```bash
talosctl -n solwk01 services
# ext-frr shows "stopped" or missing
```

**Debug Steps**:
```bash
# 1. Check ExtensionServiceConfig
talosctl -n solwk01 get machineconfig -o yaml | grep -A 50 ExtensionServiceConfig

# 2. Check FRR files exist
talosctl -n solwk01 read /usr/local/etc/frr/config.yaml
talosctl -n solwk01 read /usr/local/etc/frr/daemons

# 3. Check extension installed
talosctl -n solwk01 get extensions
# Look for frr extension

# 4. Check logs
talosctl -n solwk01 logs ext-frr
```

**Solution**:
```bash
# Ensure FRR extension is in system_extensions
vim terraform/infra/modules/talos_config/variables.tf
# Check system_extensions includes FRR

# Regenerate and re-apply
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
cd ../apply  # Need apply to update base extensions
terragrunt apply
```

---

### Problem 4: Patch Apply Failures

**Symptoms**:
```bash
cd terraform/infra/live/clusters/cluster-101/patch
terragrunt apply
# ERROR: talosctl patch failed
```

**Debug Steps**:
```bash
# 1. Check patch file generated correctly
ls -la ~/.cache/terragrunt/patches/
cat ~/.cache/terragrunt/patches/solwk01.patch.yaml

# 2. Test patch manually
talosctl -n solwk01 patch machineconfig \
  --patch @~/.cache/terragrunt/patches/solwk01.patch.yaml \
  --mode no-reboot \
  --dry-run

# 3. Check node connectivity
talosctl -n solwk01 health

# 4. Check current machine config
talosctl -n solwk01 get machineconfig -o yaml
```

**Common Causes**:
- Invalid YAML in patch
- Node not reachable
- talosconfig outdated
- Patch conflicts with base config

**Solution**:
```bash
# Validate patch YAML
yamllint ~/.cache/terragrunt/patches/solwk01.patch.yaml

# Update talosconfig
cd terraform/infra/live/clusters/cluster-101/config
terragrunt output -raw talosconfig > ~/.talos/config

# Retry patch
cd ../patch
terragrunt apply
```

---

### Problem 5: Config Drift Detection

**Scenario**: Verify node config matches Terraform state

**Steps**:
```bash
# 1. Get current config from node
talosctl -n solwk01 get machineconfig -o yaml > /tmp/node-config.yaml

# 2. Get expected config from Terraform
cd terraform/infra/live/clusters/cluster-101/config
terragrunt output -json machine_configs | \
  jq -r '.solwk01.config_patch' > /tmp/expected-patch.yaml

# 3. Compare
diff /tmp/node-config.yaml /tmp/expected-patch.yaml

# 4. If drift detected, re-apply
cd ../patch
terragrunt apply  # Sync patch
# OR
cd ../apply
terragrunt apply  # Sync base + patch
```

---

## Emergency Procedures

### Emergency 1: Rollback to Previous Config

**Scenario**: Config change caused cluster issues

**Steps**:
```bash
# 1. Identify last known good commit
cd /Users/sulibot/repos/github/home-ops
git log --oneline terraform/infra/modules/talos_config/

# 2. Revert to previous commit
git revert HEAD  # Or specific commit

# 3. Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply

# 4. Apply to nodes
cd ../apply  # Use apply for safety
terragrunt apply

# 5. Verify cluster health
kubectl get nodes
kubectl get pods -A
```

**Alternative** (Git checkout):
```bash
# Checkout previous version
git checkout HEAD~1 terraform/infra/modules/talos_config/

# Apply without committing
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
cd ../apply
terragrunt apply

# Verify, then commit if good
git add terraform/infra/modules/talos_config/
git commit -m "Rollback to working config"
```

---

### Emergency 2: Node Recovery After Failed Apply

**Scenario**: Node in bad state after config apply

**Steps**:
```bash
# 1. Check node status
talosctl -n <node-ip> health
talosctl -n <node-ip> services

# 2. If node unreachable, try recovery mode
talosctl -n <node-ip> reset --graceful=false --reboot

# 3. Re-bootstrap node
cd terraform/infra/live/clusters/cluster-101/apply
terragrunt apply

# 4. Verify node rejoins cluster
kubectl get nodes -w
```

**Nuclear option** (re-install):
```bash
# 1. Delete VM
cd terraform/infra/live/clusters/cluster-101/compute
terragrunt destroy -target=module.cluster.proxmox_vm_qemu.node[\"solwk01\"]

# 2. Recreate VM
terragrunt apply

# 3. Bootstrap node
cd ../apply
terragrunt apply
```

---

### Emergency 3: Cluster-Wide Issues

**Scenario**: Config change broke entire cluster

**Steps**:
```bash
# 1. Identify problem scope
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running

# 2. Check Talos service status on all nodes
for node in solcp{01..03} solwk{01..03}; do
  echo "=== $node ==="
  talosctl -n $node services | grep -E '(kubelet|containerd|etcd)'
done

# 3. If etcd broken, recover from snapshot
talosctl -n solcp01 etcd snapshot save snapshot.db
# Restore on new cluster if needed

# 4. If CNI broken, check Cilium
kubectl get pods -n kube-system | grep cilium
kubectl logs -n kube-system ds/cilium

# 5. Rollback config (see Emergency 1)
git revert HEAD
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
cd ../apply
terragrunt apply
```

---

## Verification Checklists

### Post-Patch Verification

Run after `patch/` stage:

```bash
# ✓ Hostname preserved
kubectl get nodes
talosctl get members

# ✓ IPs preserved (should be loopback .254 addresses)
kubectl get nodes -o wide
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'

# ✓ Routes intact
for node in solcp{01..03} solwk{01..03}; do
  echo "=== $node ==="
  talosctl -n $node get routes | grep -E '(0.0.0.0|::)'
done

# ✓ BGP sessions established
kubectl exec -n kube-system ds/cilium -- cilium bgp peers

# ✓ FRR running
for node in solcp{01..03} solwk{01..03}; do
  talosctl -n $node services ext-frr
done

# ✓ Node labels updated
kubectl get nodes --show-labels | grep <your-new-label>

# ✓ No unexpected reboots
kubectl get events --sort-by='.lastTimestamp' | grep -i reboot
```

---

### Post-Bootstrap Verification

Run after `apply/` stage (initial bootstrap):

```bash
# ✓ All nodes ready
kubectl get nodes -o wide
# Should show all 6 nodes (3 control plane, 3 workers)

# ✓ Cluster health
kubectl get pods -A
kubectl get componentstatuses

# ✓ etcd healthy
talosctl -n solcp01,solcp02,solcp03 service etcd status

# ✓ CNI running (Cilium)
kubectl get pods -n kube-system | grep cilium
kubectl exec -n kube-system ds/cilium -- cilium status

# ✓ BGP peering established
kubectl exec -n kube-system ds/cilium -- cilium bgp peers

# ✓ FRR running on all nodes
for node in solcp{01..03} solwk{01..03}; do
  echo "=== $node ==="
  talosctl -n $node services ext-frr
done

# ✓ Workloads can schedule
kubectl run test --image=nginx --restart=Never
kubectl get pods test -o wide
kubectl delete pod test
```

---

### Maintenance Window Verification

Before maintenance window:

```bash
# ✓ Backup etcd
talosctl -n solcp01 etcd snapshot save etcd-backup-$(date +%Y%m%d-%H%M%S).db

# ✓ Backup Flux state
flux export source git flux-system > flux-backup.yaml
flux export kustomization flux-system >> flux-backup.yaml

# ✓ Document current state
kubectl get nodes -o wide > pre-maintenance-nodes.txt
kubectl get pods -A -o wide > pre-maintenance-pods.txt

# ✓ Notify team
# Post in Slack/chat about maintenance window
```

After maintenance window:

```bash
# ✓ Compare state
kubectl get nodes -o wide > post-maintenance-nodes.txt
diff pre-maintenance-nodes.txt post-maintenance-nodes.txt

# ✓ Verify all workloads running
kubectl get pods -A | grep -v Running | grep -v Completed

# ✓ Run post-patch or post-bootstrap checklist (above)

# ✓ Confirm with team
# Post completion status in Slack/chat
```

---

## Quick Reference

### When to Use Each Stage

| Stage | Use Case | Safety | Frequency |
|-------|----------|--------|-----------|
| `secrets/` | Generate cluster secrets | Safe | Once |
| `compute/` | Create/modify VMs | Safe | Rare |
| `config/` | Generate configs | Safe | Every change |
| `apply/` | Bootstrap, base changes | ⚠️ Caution | Initial + base changes |
| `patch/` | Routine updates | ✅ Safe | Frequently |

### Common Commands

```bash
# Regenerate configs
cd terraform/infra/live/clusters/cluster-101/config && terragrunt apply

# Apply patch (safe)
cd terraform/infra/live/clusters/cluster-101/patch && terragrunt apply

# Apply base + patch (caution)
cd terraform/infra/live/clusters/cluster-101/apply && terragrunt apply

# Check node health
talosctl health

# Get node config
talosctl get machineconfig -o yaml

# Check BGP sessions
kubectl exec -n kube-system ds/cilium -- cilium bgp peers

# Check FRR status
talosctl -n <node> services ext-frr
talosctl -n <node> shell
vtysh -c 'show bgp summary'
```

---

## Architecture Notes

### Patch Structure

The `config_patch` output contains **TWO YAML documents** separated by `---`:

1. **Machine Config Patch**:
   - nodeLabels (topology, BGP ASN, GPU/USB tags)
   - network (hostname, interfaces, IPs, routes, MTU, DNS)
   - kubelet (nodeIP.validSubnets)
   - kernel (GPU modules if enabled)

2. **ExtensionServiceConfig Patch**:
   - FRR BGP daemon configuration
   - Per-node BGP peers, ASN, route filters
   - Daemons config (zebra, bgpd, staticd, bfdd)
   - vtysh config with hostname

Both documents are per-node and both update safely via `patch/` stage.

### Config Organization

**Truly Per-Node** (different per node):
- Hostname, IPs, loopback addresses
- Node-specific labels (GPU, USB)
- Per-node BGP ASN
- VIP (controlplane only)

**Templated Cluster Standards** (same pattern, but in patch):
- MTU (cluster-wide VXLAN overhead)
- DNS nameservers (cluster-wide)
- Default route patterns (cluster gateway)
- VLAN configuration (role-wide for workers)

**Why standards are in patch**: Talos base config is for cluster-wide, node-agnostic settings. Network configuration is inherently node-specific in Talos architecture.

### Decision Rule

**"Does this change require re-templating for ALL nodes?"**
- **YES** (MTU, DNS, VLANs, base sysctls) → Edit config, use `apply/` stage
- **NO** (single node's IP/label, per-node overrides) → Edit config, use `patch/` stage

---

**Last Updated**: 2026-02-09
**Cluster**: cluster-101
**Talos Version**: v1.9+ (adjust for your version)
