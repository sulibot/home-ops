# Debian 13 Kubernetes-Ready Template

## Overview

This Terraform configuration creates a production-ready Debian 13 VM template optimized for Kubernetes clusters. The template includes pre-built SR-IOV drivers, proper time synchronization, security hardening, and all Kubernetes prerequisites.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Template Creation Workflow                                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. Upload cloud-init configuration to Proxmox                   │
│ 2. Create VM from Debian 13 cloud image                         │
│ 3. Boot VM and execute cloud-init                               │
│    ├─ Install 70+ packages (build tools, K8s runtime, etc)     │
│    ├─ Configure security hardening (SSH, sysctl)                │
│    ├─ Setup Chrony time sync (replaces systemd-timesyncd)      │
│    ├─ Download and install i915-sriov-dkms package             │
│    ├─ Build SR-IOV drivers for current kernel                  │
│    ├─ Mask DKMS service (prevent rebuilds)                     │
│    └─ Configure GRUB with SR-IOV parameters                    │
│ 4. Wait for cloud-init completion (max 15 minutes)             │
│ 5. Verify template integrity (drivers, services, config)       │
│ 6. Clean up (SSH keys, logs, temp files)                       │
│ 7. Convert VM to template                                       │
│ 8. Verify template state                                        │
└─────────────────────────────────────────────────────────────────┘
```

## Key Features

### Pre-built SR-IOV Drivers
- **What**: Intel i915 SR-IOV drivers built during template creation
- **Why**: Eliminates 5-10 minute driver compilation on every VM boot
- **Version**: 2025.07.22 (configurable)
- **DKMS service**: Masked to prevent rebuild cycles

### Chrony Time Synchronization
- **Why Chrony**: Required for Kubernetes (systemd-timesyncd conflicts)
- **Sources**: Cloudflare, Google, NTP pool (multi-source for reliability)
- **Configuration**: Serves time to local network (K8s pods)
- **systemd-timesyncd**: Disabled and masked

### Security Hardening
- SSH ciphers restricted to modern algorithms (chacha20-poly1305, aes256-gcm)
- SSH MACs restricted (hmac-sha2-512-etm, hmac-sha2-256-etm)
- Kernel parameters for Kubernetes networking
- Log rotation configured

### Kubernetes Prerequisites
- **Container runtime**: containerd configured
- **Kernel modules**: overlay, br_netfilter, i915
- **Sysctl settings**: IP forwarding, bridge netfilter enabled

### QEMU Guest Agent
- **Status**: Enabled with virtio-serial hardware
- **Timeout**: 120 seconds (optimized from 300s)
- **Features**: IP display, graceful shutdown, snapshot coordination

## File Structure

```
terraform/live/golden/template/
├── README.md                    # This file
├── debian_template_vm.tf        # Main template VM resource
├── cloud_init.tf                # Cloud-init configuration (750 lines)
├── variables.tf                 # Input variables
├── output.tf                    # Template outputs and usage notes
└── .terraform.lock.hcl          # Provider version lock
```

## Configuration

### Hardware Specifications

| Component | Value | Rationale |
|-----------|-------|-----------|
| BIOS | UEFI (OVMF) | Modern firmware, required for Secure Boot capability |
| Secure Boot | Disabled | Faster boot, no overhead for Linux workloads |
| TPM | Not configured | Not required for Kubernetes |
| Machine Type | q35 | Modern chipset with PCIe support |
| SCSI Hardware | virtio-scsi-pci | Better performance than virtio-scsi-single |
| CPU | host (2 cores) | Pass-through host CPU features |
| Memory | 2048 MB | Sufficient for template creation |
| Disk | 16 GB (Ceph RBD) | Base size, expanded in cloned VMs |
| Cache | writeback | Best performance with Ceph |
| Discard | Enabled | TRIM support for thin provisioning |
| I/O Thread | Enabled | Dedicated I/O thread for disk operations |

### Storage Layout

- **VM disk**: `rbd-vm` (Ceph RBD) - Template disk stored on Ceph
- **EFI vars**: `local` storage - Reliability (keep off Ceph)
- **Clone type**: Full clones recommended for cross-node placement

## Usage

### Prerequisites

1. Proxmox cluster with Ceph storage
2. Debian 13 cloud image uploaded to Proxmox
3. Terraform >= 1.0
4. bpg/proxmox provider >= 0.83.0

### Creating the Template

```bash
cd /Users/sulibot/repos/github/home-ops/terraform/live/golden/template

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Create the template (takes ~12-15 minutes)
terraform apply
```

### Template Creation Timeline

| Phase | Duration | What's Happening |
|-------|----------|------------------|
| VM Creation | ~30s | Cloning from cloud image, allocating storage |
| Package Installation | ~5-7 min | Installing 70+ packages (build-essential, containerd, etc) |
| SR-IOV Driver Build | ~3-5 min | Compiling i915-sriov-dkms for current kernel |
| Configuration | ~1-2 min | Chrony setup, security hardening, GRUB config |
| Verification | ~30s | Checking drivers, services, configuration |
| Template Conversion | ~10s | Converting VM to template |
| **Total** | **~12-15 min** | |

### Cloning VMs from Template

```bash
# Via Proxmox CLI
qm clone 9000 101011 --full --name solcp011

# Via Terraform (recommended)
# See: terraform/modules/clusters/cluster/instance_group/main.tf
```

**Important**: Always use `full = true` for clones that need to be placed on different nodes.

## Verification

### After Template Creation

```bash
# Check template state
qm config 9000

# Verify it's marked as template
qm config 9000 | grep template

# Expected output:
# template: 1
```

### After Cloning a VM

```bash
# SSH into cloned VM
ssh root@<vm-ip>

# Verify SR-IOV drivers
dkms status | grep i915-sriov
# Expected: i915-sriov-dkms/2025.07.22, 6.1.0-XX-amd64, x86_64: installed

# Verify DKMS is masked (should NOT rebuild on boot)
systemctl is-enabled dkms.service
# Expected: masked

# Check SR-IOV module loaded
lsmod | grep i915
# Expected: i915 module listed

# Verify Chrony time sync
systemctl status chrony
chronyc tracking
# Expected: System time synchronized

# Verify systemd-timesyncd is disabled
systemctl is-enabled systemd-timesyncd
# Expected: masked

# Check QEMU guest agent
systemctl status qemu-guest-agent
ls -l /dev/virtio-ports/org.qemu.guest_agent.0
# Expected: Service running, device present

# Verify containerd
systemctl status containerd
# Expected: Active (running)

# Check kernel modules
lsmod | grep -E 'overlay|br_netfilter'
# Expected: Both modules loaded

# Verify GRUB configuration
grep intel_iommu /proc/cmdline
# Expected: intel_iommu=on i915.enable_guc=3 i915.max_vfs=7
```

## Troubleshooting

### Template Creation Hangs

**Symptom**: Terraform stuck at "Still creating..." for >15 minutes

**Causes**:
- Cloud-init taking longer than expected
- Package download failures
- SR-IOV driver build failures

**Debug**:
```bash
# SSH into the template VM during creation
ssh root@<template-ip>

# Check cloud-init status
cloud-init status --long

# Check cloud-init logs
tail -f /var/log/cloud-init-output.log

# Check if completion marker exists
ls -l /tmp/golden-cloud-config.done
```

**Fix**:
- Increase `TIMEOUT` in [debian_template_vm.tf:108](debian_template_vm.tf#L108) (currently 900s)
- Check network connectivity to download sources
- Verify Debian package mirrors are accessible

### SR-IOV Drivers Not Present

**Symptom**: `dkms status | grep i915-sriov` returns empty

**Causes**:
- SR-IOV package download failed
- DKMS build failed during template creation

**Debug**:
```bash
# Check if package was downloaded
ls -l /tmp/i915-sriov-dkms_*.deb

# Check DKMS build logs
dmesg | grep i915
journalctl -u dkms
```

**Fix**:
- Check cloud-init logs during template creation
- Verify network access to GitHub releases
- Consider adding package checksum validation (see Optimization section)

### QEMU Guest Agent Not Running

**Symptom**: `systemctl status qemu-guest-agent` shows "Dependency failed"

**Cause**: Missing virtio-serial hardware (agent.enabled = false)

**Fix**: Ensure [debian_template_vm.tf:34](debian_template_vm.tf#L34) has:
```hcl
agent {
  enabled = true  # This adds virtio-serial hardware
}
```

### Time Sync Issues in Kubernetes

**Symptom**: Kubernetes certificate errors, time drift warnings

**Debug**:
```bash
# Check Chrony status
chronyc tracking
# Look for "System time" offset

# Check time sources
chronyc sources
# Verify multiple sources are reachable

# Check systemd-timesyncd is disabled
systemctl is-enabled systemd-timesyncd
# MUST show "masked"
```

**Fix**:
- Verify Chrony configuration in [cloud_init.tf:131-157](cloud_init.tf#L131-L157)
- Ensure systemd-timesyncd is masked in [cloud_init.tf:715](cloud_init.tf#L715)

### Clone Fails with "Migration Aborted"

**Symptom**: VMs fail to clone to different nodes

**Cause**: Using linked clones (`full = false`) with Ceph storage

**Fix**: Use full clones when VMs need cross-node placement:
```hcl
clone {
  vm_id     = 9000
  node_name = "pve01"  # Template location
  full      = true      # Required for cross-node with RBD
}
```

## Optimization Opportunities

### 1. Parameterize SR-IOV Version

**Current**: Version hardcoded in [cloud_init.tf:213](cloud_init.tf#L213)

**Improvement**: Add variable to [variables.tf](variables.tf):
```hcl
variable "sriov_version" {
  type        = string
  description = "Version of i915-sriov-dkms to install"
  default     = "2025.07.22"
}
```

Then reference in cloud-init: `SRIOV_VERSION="${var.sriov_version}"`

### 2. Add Package Checksum Validation

**Current**: No checksum verification for downloaded .deb package

**Security Risk**: Potential for tampered or corrupted packages

**Improvement**: Add SHA256 validation in [cloud_init.tf:237-255](cloud_init.tf#L237-L255):
```bash
EXPECTED_SHA256="<checksum-here>"
ACTUAL_SHA256=$(sha256sum "$DEB_FILE" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "ERROR: Checksum mismatch!"
  exit 1
fi
```

### 3. Reduce Cloud-init Timeout

**Current**: 900 seconds (15 minutes) in [debian_template_vm.tf:108](debian_template_vm.tf#L108)

**Typical completion**: ~10-12 minutes

**Recommendation**: Monitor actual completion times, potentially reduce to 600s (10 min)

### 4. Add Exponential Backoff to Downloads

**Current**: Fixed retry delay in [cloud_init.tf:230-267](cloud_init.tf#L230-L267)

**Improvement**: Exponential backoff (5s, 10s, 20s) for better resilience

## Performance Metrics

### Template Creation
- **Initial build**: ~12-15 minutes (one-time cost)
- **SR-IOV compilation**: ~3-5 minutes (avoided on every VM boot)
- **Package installation**: ~5-7 minutes (avoided on every VM boot)

### VM Cloning from Template
- **Full clone**: ~30-40 seconds per VM
- **Linked clone**: ~10 seconds (not recommended for cross-node placement)

### VM Boot Time (from template)
- **Total boot**: ~60-120 seconds with agent enabled
- **Without template**: Would add 5-10 minutes for SR-IOV compilation

### ROI Calculation
If deploying 6 VMs:
- **Without template**: 6 × 15 min = 90 minutes
- **With template**: 15 min (template) + 6 × 2 min (clones) = 27 minutes
- **Savings**: 63 minutes (70% faster)

## Maintenance

### Updating SR-IOV Version

1. Update version in [cloud_init.tf:213](cloud_init.tf#L213) (or use variable approach)
2. Destroy and recreate template:
```bash
terraform destroy
terraform apply
```

3. Or update running template VM:
```bash
ssh root@<template-ip>
/usr/local/bin/update-sriov.sh <new-version>
# Then reconvert to template
```

### Updating Packages

Cloud-init installs latest versions at template creation time. To update:

1. Recreate template (recommended):
```bash
terraform destroy
terraform apply
```

2. Or update running template:
```bash
qm template 9000 --delete  # Convert back to VM
qm start 9000
ssh root@<template-ip>
apt update && apt upgrade -y
# Clean up before reconverting
qm shutdown 9000
qm template 9000  # Reconvert to template
```

### Adding New Packages

Edit [cloud_init.tf:638-706](cloud_init.tf#L638-L706) and add packages to the list:
```yaml
packages:
  - your-new-package
  - another-package
```

Then recreate template: `terraform destroy && terraform apply`

## Integration with Cluster Provisioning

This template is consumed by the cluster provisioning module:

```
terraform/modules/clusters/cluster/instance_group/main.tf
└─> Clones from template VM ID 9000
    ├─> Creates control plane nodes (101011, 101012, 101013)
    └─> Creates worker nodes (101021, 101022, 101023)
```

Configuration in cluster module:
```hcl
clone {
  vm_id     = var.template_vmid  # 9000
  node_name = local.proxmox_instances[0]
  full      = true  # Full clone for cross-node placement
}

agent {
  enabled = true  # Enable guest agent features
}

timeout_create   = 180  # 3 minutes max for VM creation
timeout_start_vm = 120  # 2 minutes max for VM start
```

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [i915-sriov-dkms Repository](https://github.com/strongtz/i915-sriov-dkms)
- [Kubernetes System Requirements](https://kubernetes.io/docs/setup/production-environment/)
- [Chrony vs systemd-timesyncd](https://chrony.tuxfamily.org/)

## Support

For issues with:
- **Template creation**: Check cloud-init logs, verify network connectivity
- **SR-IOV drivers**: Verify kernel headers installed, check DKMS logs
- **Time sync**: Verify Chrony configuration, check NTP source reachability
- **Guest agent**: Verify virtio-serial device present, check agent service logs

## Changelog

### 2025-11-02
- Optimized agent timeout: 300s → 120s
- Optimized cloud-init timeout: 1800s → 900s
- Fixed SCSI hardware: virtio-scsi-single → virtio-scsi-pci
- Disabled Secure Boot: pre_enrolled_keys = false
- Aligned template config with VM configurations

### 2025-07-22
- Updated SR-IOV driver version to 2025.07.22
- Added Chrony time synchronization for Kubernetes
- Masked systemd-timesyncd to prevent conflicts
- Added security hardening (SSH ciphers/MACs)

### Initial Release
- Debian 13 cloud image base
- Pre-built SR-IOV drivers
- DKMS service masking
- Comprehensive verification scripts
