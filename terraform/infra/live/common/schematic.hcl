# Talos image schematic configuration
# Converted from talos/common/schematic.yaml.j2

locals {
  # Format compatible with existing talos_proxmox_image module
  talos_extra_kernel_args = [
    "-init_on_alloc",        # Less security, faster performance
    "-init_on_free",         # Less security, faster performance
    "-selinux",              # Less security, faster performance
    "apparmor=0",            # Less security, faster performance
    "i915.enable_guc=3",     # Meteor Lake CPU & Intel iGPU
    "init_on_alloc=0",       # Less security, faster performance
    "init_on_free=0",        # Less security, faster performance
    "intel_iommu=on",        # PCI Passthrough
    "iommu=pt",              # PCI Passthrough
    "mitigations=off",       # Less security, faster performance
    "module_blacklist=igc",  # Disable onboard NIC
    "security=none",         # Less security, faster performance
    "sysctl.kernel.kexec_load_disabled=1",  # Meteor Lake CPU & Intel iGPU
    "talos.auditd.disabled=1",  # Less security, faster performance
  ]

  # Official Siderolabs extensions (as flat list)
  talos_system_extensions = [
    "siderolabs/cloudflared",
    "siderolabs/i915",
    "siderolabs/intel-ucode",
    "siderolabs/qemu-guest-agent",
    "siderolabs/util-linux-tools",
    "siderolabs/zfs",
    "siderolabs/nfsd",
    "siderolabs/nfsrahead",
  ]

  # Talos patches (if any)
  talos_patches = []

  # New format for talos_config and talos_bootstrap modules
  schematic = {
    kernel_args = local.talos_extra_kernel_args
    system_extensions = {
      official = local.talos_system_extensions
      custom   = []
    }
    allow_unsigned_extensions = false
  }
}
