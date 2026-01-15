# Cluster Rebuild Workflow

## Overview

This document describes the safe workflow for rebuilding the Kubernetes cluster from scratch while preserving Talos machine secrets and enabling automatic application restore via VolSync.

## Prerequisites

- Existing cluster backup via VolSync/Kopia
- Talos secrets stored in `talos/clusters/cluster-101/secrets.sops.yaml`
- Terraform state intact
- SOPS keys available for secret decryption

## Rebuild Workflow

### Standard Rebuild (Preserves Secrets)

This is the recommended approach for normal cluster rebuilds:

```bash
# Navigate to cluster directory
cd terraform/infra/live/clusters/cluster-101

# Destroy infrastructure (automatically preserves secrets)
terragrunt destroy --all --non-interactive -auto-approve

# Wait for VMs to be fully deleted
sleep 15

# Rebuild cluster from scratch
terragrunt apply --all --non-interactive -auto-approve
```

**What happens:**
1. ✅ VMs destroyed
2. ✅ Talos machine secrets preserved (automatically skipped)
3. ✅ Cluster rebuilt with same secrets
4. ✅ VolSync automatically restores application data
5. ✅ Applications start with restored data

### Handling Bootstrap State Errors

If you encounter Kubernetes API unreachable errors during destroy (because cluster is already gone):

```bash
cd terraform/infra/live/clusters/cluster-101

# Destroy VMs first (forces cleanup)
cd compute
terragrunt destroy --non-interactive -auto-approve

# Attempt to destroy bootstrap (will error, that's OK)
cd ../bootstrap
terragrunt destroy --non-interactive -auto-approve || true

# Clean up any remaining state
cd ../config
terragrunt destroy --non-interactive -auto-approve || true

cd ../apply
terragrunt destroy --non-interactive -auto-approve || true

# Rebuild everything
cd ..
terragrunt apply --all --non-interactive -auto-approve
```

### Full Rebuild with Fresh Secrets (DESTRUCTIVE)

⚠️ **WARNING**: Only use this if you need to completely regenerate Talos secrets (rare).

```bash
cd terraform/infra/live/clusters/cluster-101

# Destroy EVERYTHING including secrets
TALOS_DESTROY_SECRETS=1 terragrunt destroy --all --non-interactive -auto-approve

# Rebuild with new secrets
terragrunt apply --all --non-interactive -auto-approve
```

**Consequences:**
- ❌ Talos machine secrets regenerated (new cluster identity)
- ❌ Kubernetes CA certificates regenerated
- ❌ All kubeconfigs must be updated
- ❌ May require manual VolSync restore if repository keys change

## Secret Protection Mechanism

The `secrets` Terragrunt module automatically protects Talos secrets from accidental deletion:

**File**: `terraform/infra/live/clusters/cluster-101/secrets/terragrunt.hcl:7-11`
```hcl
locals {
  terragrunt_command = lower(trimspace(get_env("TERRAGRUNT_COMMAND", "")))
  destroy_secrets    = get_env("TALOS_DESTROY_SECRETS", "") != ""
  skip_destroy       = can(regex("destroy", local.terragrunt_command)) && !local.destroy_secrets
}

skip = local.skip_destroy
```

**How it works:**
- During `destroy` commands: `skip = true` (secrets preserved)
- With `TALOS_DESTROY_SECRETS=1`: `skip = false` (secrets destroyed)
- During `apply` commands: `skip = false` (secrets created/updated)

## What Gets Destroyed/Preserved

### Always Destroyed
- ✅ Proxmox VMs (compute, control plane, workers)
- ✅ Cloud-init configurations
- ✅ Talos bootstrap state
- ✅ Flux GitOps state
- ✅ Kubernetes cluster state

### Always Preserved (Standard Rebuild)
- ✅ Talos machine secrets
- ✅ Kubernetes certificates
- ✅ VolSync backup repository
- ✅ Application data in Kopia backups
- ✅ Git repository configuration

### Only Destroyed with `TALOS_DESTROY_SECRETS=1`
- ⚠️ Talos cluster secrets
- ⚠️ Machine tokens
- ⚠️ Certificate authorities

## Post-Rebuild Verification

### 1. Check VM Creation

```bash
# Verify VMs are running
talosctl --nodes 10.101.0.10,10.101.0.11,10.101.0.12 version

# Check all nodes (CP + workers)
talosctl --nodes 10.101.0.10,10.101.0.11,10.101.0.12,10.101.0.20,10.101.0.21,10.101.0.22 get members
```

### 2. Check Network Interfaces

Worker nodes should have `ens19` for Multus VLAN trunking:

```bash
# Check worker nodes have ens19
talosctl --nodes 10.101.0.20,10.101.0.21,10.101.0.22 get links

# Expected output: ens18 (management) and ens19 (VLAN trunk)
```

### 3. Monitor VolSync Restores

```bash
# Check ReplicationDestination status
kubectl get replicationdestination -A

# Monitor specific app restore
watch kubectl get replicationdestination plex-dst -n default

# Check for VolumeSnapshots being created
kubectl get volumesnapshot -A

# Check PVC binding
kubectl get pvc -A | grep -E 'plex|prometheus|home-assistant'
```

### 4. Check Application Pods

```bash
# All pods should eventually transition from Pending → Running
kubectl get pods -A

# Monitor specific app
kubectl get pod -n default -l app.kubernetes.io/name=plex -w
```

### 5. Verify Multus Networking

For apps using VLAN networks (Plex, Home Assistant):

```bash
# Check NetworkAttachmentDefinitions
kubectl get network-attachment-definitions -n default

# Check pod network annotations
kubectl get pod -n default -l app.kubernetes.io/name=plex -o yaml | grep networks

# Verify pod has VLAN interface
kubectl exec -n default <plex-pod> -- ip addr show
```

## Restore Timeline

Typical restore times after cluster rebuild:

| Phase | Duration | What's Happening |
|-------|----------|------------------|
| VM Creation | 2-5 min | Proxmox creates VMs, Talos boots |
| Talos Bootstrap | 3-5 min | etcd cluster forms, Kubernetes starts |
| Flux Bootstrap | 2-3 min | Flux installs, syncs from Git |
| VolSync Restore Start | 1-2 min | ReplicationDestinations created |
| Data Restore (small) | 5-15 min | Kopia restores < 10GB apps |
| Data Restore (large) | 15-60 min | Kopia restores > 10GB apps (Plex) |
| Pod Startup | 1-5 min | Containers start after PVC binds |

**Total rebuild time**: 30-90 minutes depending on data size and parallelism.

## Troubleshooting

### Issue: "Kubernetes cluster unreachable" During Destroy

**Symptom:**
```
Error: Kubernetes cluster
failed to get server groups: Get "https://[fd00:101::10]:6443/api": dial
tcp [fd00:101::10]:6443: connect: network is unreachable
```

**Solution:** The Flux bootstrap resource now has lifecycle `ignore_changes = all` configured, which prevents this error during destroy. However, you'll need to clean up Terraform state manually after destroying a cluster:

```bash
cd terraform/infra/live/clusters/cluster-101/bootstrap
terragrunt state rm 'flux_bootstrap_git.this[0]'
```

This is safe because Flux resources are automatically removed when VMs are destroyed.

### Issue: Secrets Not Preserved

**Symptom:** Talos rejects machine config, kubeconfig doesn't work

**Check:**
```bash
# Verify secrets file exists
ls -lh talos/clusters/cluster-101/secrets.sops.yaml

# Check Terraform state
cd terraform/infra/live/clusters/cluster-101/secrets
terragrunt state list
```

**Solution:** If secrets were accidentally destroyed, you must:
1. Generate new secrets: `terragrunt apply` in secrets module
2. Rebuild cluster completely with new identity

### Issue: Orphaned RBD Images Blocking VM Creation

**Symptom:**
```
Error: rbd create 'vm-101012-cloudinit' error: (17) File exists
Error: error get file rbd-vm:vm-101021-disk-1: rbd: error opening image (2) No such file or directory
```

**Cause:** During `terragrunt destroy`, Proxmox doesn't always successfully delete RBD (Ceph) images, especially when VMs are force-stopped with `stop_on_destroy = true`. This leaves orphaned images that block subsequent VM creation.

**Solution:** Clean up orphaned RBD images manually before re-applying:

```bash
# Check for orphaned images
ssh root@10.10.0.1 'rbd ls rbd-vm | grep "^vm-1010[12][0-3]-"'

# Remove all orphaned images for cluster 101
ssh root@10.10.0.1 'for img in $(rbd ls rbd-vm | grep "^vm-1010[12][0-3]-"); do echo "Removing $img"; rbd rm rbd-vm/$img; done'
```

**Note:** This cleanup is safe because these are orphaned images from destroyed VMs. The RBD pool is shared across all Proxmox nodes, so cleanup from any node removes the images cluster-wide.

### Issue: VolSync Restores Not Starting

**Symptom:** ReplicationDestination stuck in pending, no restore pods

**Check:**
```bash
# Verify VolSync operator running
kubectl get pods -n volsync-system

# Check Kopia repository access
kubectl get pvc -n volsync-system

# Check for errors
kubectl describe replicationdestination <name> -n <namespace>
```

**Solution:**
```bash
# Force Flux reconciliation
flux reconcile kustomization <app> -n flux-system

# Check VolSync logs
kubectl logs -n volsync-system -l app.kubernetes.io/name=volsync
```

### Issue: Multus VLAN Networks Not Working

**Symptom:** Pods stuck in `ContainerCreating` with "Link not found" error

**Check:**
```bash
# Verify ens19 exists on worker nodes
talosctl --nodes 10.101.0.20,10.101.0.21,10.101.0.22 get links | grep ens19

# Check NetworkAttachmentDefinition
kubectl get net-attach-def -n default vlan30 -o yaml
```

**Solution:**
```bash
# Verify Terraform added second NIC to workers
cd terraform/infra/live/clusters/cluster-101/compute
terragrunt plan | grep -A10 "network_device"

# If missing, apply compute module
terragrunt apply
```

## Validation Commands

These commands verify the rebuild without making changes:

```bash
# 1. Check Terraform will preserve secrets
cd terraform/infra/live/clusters/cluster-101
terragrunt plan --all

# Expected: secrets module shows "No changes" or is skipped

# 2. Verify secrets exist before rebuild
ls -lh talos/clusters/cluster-101/secrets.sops.yaml

# 3. Check VolSync backup repository exists
kubectl get pvc -n volsync-system kopia

# 4. Verify Kopia snapshots exist
kubectl exec -n volsync-system <kopia-pod> -- kopia snapshot list

# 5. Test secret decryption
sops -d talos/clusters/cluster-101/secrets.sops.yaml | grep -A5 cluster
```

## Network Configuration Changes

This rebuild includes updated network configuration for Multus VLAN support:

### Worker Node Configuration

**File**: `terraform/infra/modules/cluster_core/main.tf:411-421`

Worker nodes now have two network interfaces:
- **ens18**: Management network (vnet101 SDN)
- **ens19**: VLAN trunk (vmbr0 bridge)

### Multus NetworkAttachmentDefinitions

**Files:**
- `kubernetes/apps/networking/multus/networks/vlan30.yaml` - IoT network
- `kubernetes/apps/networking/multus/networks/vlan31.yaml` - Additional VLAN

Both use macvlan on `ens19` master interface with VLAN tagging.

### Applications Using VLANs

- **Plex**: Requires VLAN 30 for IoT device access
- **Home Assistant**: Requires VLAN 30 for IoT device access

## Related Documentation

- [VOLSYNC_AUTOMATIC_RESTORE.md](./VOLSYNC_AUTOMATIC_RESTORE.md) - Automatic restore system details
- [VOLSYNC_KOPIA_BACKUP_SYSTEM.md](./VOLSYNC_KOPIA_BACKUP_SYSTEM.md) - Backup architecture
- [ip-addressing-layout.md](./ip-addressing-layout.md) - Network IP allocation

## Emergency Procedures

### Break-Glass: Manual Application Restore

If VolSync automatic restore fails, manually create PVC:

```bash
# Example: Plex manual restore
kubectl apply -f kubernetes/apps/applications/plex/app/manual-plex-config-pvc.yaml

# Then manually restore from Kopia
kubectl exec -n volsync-system <kopia-pod> -- kopia snapshot restore <snapshot-id> /data/plex-config
```

### Break-Glass: Rebuild Without Preserving Secrets

If cluster secrets are corrupted and you need fresh start:

```bash
# 1. Backup current secrets
cp talos/clusters/cluster-101/secrets.sops.yaml talos/clusters/cluster-101/secrets.sops.yaml.backup

# 2. Destroy everything including secrets
cd terraform/infra/live/clusters/cluster-101
TALOS_DESTROY_SECRETS=1 terragrunt destroy --all --non-interactive -auto-approve

# 3. Rebuild with fresh secrets
terragrunt apply --all --non-interactive -auto-approve

# 4. Note: You'll need to update all kubeconfigs and may need manual VolSync restoration
```
