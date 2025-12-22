# Cluster Upgrade Guide

This guide explains how to handle different types of upgrades for cluster-101.

## Understanding the Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ images/                                                      │
│  ├─ 1-talos-install-image-build/ → installer image (ghcr.io)│
│  ├─ 2-talos-boot-iso-build/ → boot ISO (local file)        │
│  └─ 3-boot-iso-upload/ → ISO on Proxmox                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ├──────────────────────┐
                              ▼                      ▼
┌─────────────────────────────────────┐   ┌──────────────────┐
│ cluster/                             │   │ Installed Talos  │
│  ├─ 1-talos-vms-create/             │──▶│ (on disk)        │
│  │    Uses: Boot ISO                │   │ Extensions baked │
│  ├─ 2-machine-config-generate/      │   │ in from installer│
│  │    Uses: Installer image ref     │   └──────────────────┘
│  └─ 3-cluster-bootstrap/            │
│       Applies: Machine configs       │
└─────────────────────────────────────┘
```

## Upgrade Scenarios

### Scenario 1: Machine Config Changes (No Extension Updates)

**Examples:**
- Change BGP configuration
- Update DNS servers
- Modify network settings
- Change node labels

**Process:**
```bash
cd cluster/2-machine-config-generate
terragrunt apply

cd ../3-cluster-bootstrap
terragrunt apply
```

**What Happens:**
- ✅ Machine configs regenerated
- ✅ Configs reapplied to running nodes
- ✅ Talos reconfigures without reboot (for most changes)
- ⚠️ Some changes may require node reboot (Talos will indicate)

**Installed Extensions:** No change - extensions remain as originally installed

---

### Scenario 2: Extension Updates (Security Patches, Bug Fixes)

**Examples:**
- qemu-guest-agent security patch (same version, new digest)
- FRR bug fix update
- Intel microcode update

**⚠️ Critical:** Extensions are baked into the installed Talos system. Updating machine configs **will not** update extensions on existing nodes.

**Process - Full Rebuild Required:**

```bash
# Step 1: Update extension digests
# Edit: terraform/infra/live/common/install-schematic.hcl
# Update SHA256 digests for affected extensions

# Step 2: Rebuild images
cd images
terragrunt run-all apply

# Step 3: Destroy and recreate cluster
cd ../cluster
terragrunt run-all destroy --terragrunt-non-interactive
terragrunt run-all apply

# Step 4: Restore cluster state
kubectl apply -f your-backup/ --recursive
# OR wait for Flux to reconcile
```

**Alternative - Rolling Update:**

For production, use Talos upgrade controller or manual node-by-node:

```bash
# For each node:
talosctl --nodes solcp01 upgrade \
  --image ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5 \
  --preserve

# Talos will:
# - Download new installer image
# - Reinstall system with new extensions
# - Preserve data and configs
# - Reboot node
```

---

### Scenario 3: Talos Version Upgrade

**Examples:**
- v1.11.5 → v1.12.0
- Minor version update
- Kubernetes version bump

**Process:**

```bash
# Step 1: Update version
# Edit: terraform/infra/live/common/versions.hcl
# Update talos_version and kubernetes_version

# Step 2: Rebuild images with new version
cd images
terragrunt run-all apply

# Step 3: Update machine configs
cd ../cluster/2-machine-config-generate
terragrunt apply

# Step 4: Perform rolling upgrade (DO NOT destroy cluster!)
cd ../3-cluster-bootstrap
terragrunt apply  # This will update configs

# Step 5: Upgrade nodes using talosctl
talosctl --nodes solcp01,solcp02,solcp03 upgrade \
  --image ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0 \
  --preserve

talosctl --nodes solwk01,solwk02,solwk03 upgrade \
  --image ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0 \
  --preserve
```

**What Happens:**
- ✅ Images built with new Talos version
- ✅ Machine configs updated for new version
- ✅ talosctl upgrade performs rolling update
- ✅ Zero downtime (control plane HA maintained)
- ✅ Extensions updated to new Talos version

---

## Stale State Protection

### When VMs Might Have Old Extensions

**Problem:** VMs exist with old installer, but images have been rebuilt.

**Detection:**
```bash
# Check installed Talos version on nodes
talosctl --nodes solcp01 version

# Check expected version in images
cd images/1-talos-install-image-build
terragrunt output installer_image

# Compare versions
```

**Solution:**
If versions don't match, use `talosctl upgrade` (Scenario 2 or 3 above).

### Preventing Stale State

**Best Practice:** Always use `talosctl upgrade` for version/extension updates, not `terragrunt apply`.

**Terragrunt is for:**
- ✅ Initial cluster deployment
- ✅ Machine config updates
- ✅ Adding/removing nodes
- ✅ Network configuration changes

**Talosctl is for:**
- ✅ Talos version upgrades
- ✅ Extension updates (via upgrade)
- ✅ System maintenance

---

## Quick Reference

| Change Type | Rebuild Images? | Destroy Cluster? | Method |
|-------------|----------------|------------------|---------|
| Machine config | ❌ | ❌ | `terragrunt apply` in cluster/ |
| Extension patch | ✅ | ❌ | `terragrunt apply` in images/, then `talosctl upgrade` |
| Talos version | ✅ | ❌ | `terragrunt apply` in images/, then `talosctl upgrade` |
| Full rebuild | ✅ | ✅ | `terragrunt run-all destroy/apply` |

---

## Safety Checklist

Before any upgrade:

- [ ] Backup etcd: `talosctl etcd snapshot`
- [ ] Backup Flux configs: `flux export --all > cluster-backup.yaml`
- [ ] Test in non-production first
- [ ] Check Talos release notes for breaking changes
- [ ] Verify extension compatibility with new Talos version
- [ ] Ensure cluster has enough capacity for rolling upgrade

---

## Rollback Procedures

### If Upgrade Fails

```bash
# Roll back to previous installer image
talosctl --nodes NODE upgrade \
  --image ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5 \
  --preserve

# Restore machine configs
cd cluster/2-machine-config-generate
git checkout HEAD~1 -- .
terragrunt apply

cd ../3-cluster-bootstrap
terragrunt apply
```

### If Cluster is Broken

```bash
# Nuclear option: Full rebuild
cd cluster
terragrunt run-all destroy
terragrunt run-all apply

# Restore from backup
kubectl apply -f cluster-backup.yaml
```
