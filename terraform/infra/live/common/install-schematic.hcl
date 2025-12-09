# Install schematic for actual system
# Full configuration with all kernel args and extensions

locals {
  # Pull versions so we can tag extensions correctly
  # Explicit path so it works from .terragrunt-cache during run-all
  versions = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/versions.hcl").locals

  # Kernel args for production system (metal platform)
  install_kernel_args = [
    "talos.platform=metal",  # Use metal platform for bare metal/VM installation
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

  # Full install extensions for Talos v1.11.5
  # For simplicity, use individual extensions tagged for v1.11
  install_system_extensions = [
    "siderolabs/i915-ucode",
    "siderolabs/intel-ucode",
    "siderolabs/qemu-guest-agent",
    "siderolabs/crun",
    "siderolabs/ctr",
    "siderolabs/bird2",
  ]

  # Custom third-party extensions
  # COMMENTED OUT: FRR extension (replaced by BIRD2)
  # To rollback to FRR, uncomment the line below and remove BIRD2 from install_system_extensions
  install_custom_extensions = [
    # "ghcr.io/sulibot/frr-talos-extension:v1.0.15",
  ]
}
