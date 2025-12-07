# Install schematic for actual system
# Full configuration with all kernel args and extensions

locals {
  # Pull versions so we can tag extensions correctly
  # Explicit path so it works from .terragrunt-cache during run-all
  versions = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/versions.hcl").locals

  # Extensions may lag Talos releases; allow overriding independently of Talos version
  extensions_version = try(local.versions.extension_version, local.versions.talos_version)

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

  # Full install extensions (individual images, not bundle)
  # v1.12.0-beta.1 imager doesn't support beta.0 bundle format with descriptions.yaml
  install_system_extensions = [
    "ghcr.io/siderolabs/i915:${local.versions.talos_version}",
    "ghcr.io/siderolabs/intel-ucode:${local.versions.talos_version}",
    "ghcr.io/siderolabs/qemu-guest-agent:${local.versions.talos_version}",
    "ghcr.io/siderolabs/util-linux-tools:${local.versions.talos_version}",
    "ghcr.io/siderolabs/zfs:${local.versions.talos_version}",
    "ghcr.io/siderolabs/nfsd:${local.versions.talos_version}",
    "ghcr.io/siderolabs/nfsrahead:${local.versions.talos_version}",
  ]

  # Custom third-party extensions
  install_custom_extensions = [
    "ghcr.io/sulibot/frr-talos-extension:v1.0.15",
  ]
}
