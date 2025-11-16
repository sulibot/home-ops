# ===== ./output.tf =====
# outputs.tf for template creation
output "template_vm_id" {
  description = "The VM ID of the created template"
  value       = proxmox_virtual_environment_vm.debian_template.vm_id
}

output "template_name" {
  description = "The name of the created template"
  value       = proxmox_virtual_environment_vm.debian_template.name
}

output "template_node" {
  description = "The Proxmox node where the template is stored"
  value       = proxmox_virtual_environment_vm.debian_template.node_name
}

output "cloud_init_file_id" {
  description = "The cloud-init file ID used for the template"
  value       = proxmox_virtual_environment_file.user_data_cloud_config.id
}

output "template_ready" {
  description = "Indicates if the template creation is complete"
  value       = null_resource.verify_template_state.id != null # <-- Simplified boolean check
}

output "template_usage_notes" {
  description = "Important notes about using this template"
  value = <<-EOT
=============================================================================
KUBERNETES-READY TEMPLATE
=============================================================================

Template VM ID: ${proxmox_virtual_environment_vm.debian_template.vm_id}
Template Name: ${proxmox_virtual_environment_vm.debian_template.name}
Node: ${proxmox_virtual_environment_vm.debian_template.node_name}

IMPORTANT INFORMATION:
- This template has SR-IOV drivers PRE-BUILT
- DKMS service is DISABLED (masked)
- Chrony configured for Kubernetes time sync
- VMs cloned from this template will NOT rebuild drivers
- No DKMS-related code needed in VM cloud-init templates

TEMPLATE INCLUDES:
✓ Pre-built i915 SR-IOV drivers (version 2025.07.22)
✓ Disabled DKMS service (no ordering cycles)
✓ Chrony time synchronization (Kubernetes-ready)
✓ systemd-timesyncd disabled (no conflicts)
✓ Containerd configured for Kubernetes
✓ Security hardening applied (SSH ciphers/MACs restricted)
✓ Log rotation configured
✓ Performance optimizations
✓ Monitoring scripts (BGP, disk space)
✓ Split-brain protection for VIPs
✓ GRUB configured with SR-IOV parameters
✓ qemu-guest-agent enabled

USAGE:
1. Clone with full-clone mode for best performance
2. Use your VM cloud-init template (remove all DKMS code from it)
3. First boot will be faster (no driver compilation)
4. Verify SR-IOV after boot: lsmod | grep i915
5. Verify time sync: chronyc tracking

TO CLONE:
  qm clone ${proxmox_virtual_environment_vm.debian_template.vm_id} <new-vmid> --full --name <new-name>

TO UPDATE SR-IOV VERSION (in running VM from this template):
  /usr/local/bin/update-sriov.sh <new-version>

TO CHECK TIME SYNC (critical for K8s):
  /usr/local/bin/check-k8s-time-sync.sh

=============================================================================
EOT
}

output "verification_commands" {
  description = "Commands to verify template after cloning"
  value = <<-EOT
Run these commands on a cloned VM to verify template integrity:

# Check SR-IOV drivers
dkms status | grep i915-sriov

# Verify DKMS service is disabled
systemctl is-enabled dkms.service  # Should show "masked"

# Check module files
ls -la /lib/modules/$(uname -r)/updates/dkms/

# Verify module loads (after reboot)
lsmod | grep i915

# Check GRUB configuration
grep intel_iommu /proc/cmdline

# Check containerd
systemctl status containerd

# Check chrony (critical for K8s)
systemctl status chrony
chronyc tracking
chronyc sources

# Verify systemd-timesyncd is disabled
systemctl is-enabled systemd-timesyncd  # Should show "masked"

# Run full verification script
/usr/local/bin/verify-template-ready.sh

# Verify SR-IOV capability
/usr/local/bin/verify-sriov.sh

# Check K8s time sync requirements
/usr/local/bin/check-k8s-time-sync.sh

# Check BGP
vtysh -c "show bgp summary"
EOT
}