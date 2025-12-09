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

  # Full install extensions - individual extension images extracted from v1.12.0-beta.1 bundle
  # Using digests to avoid descriptions.yaml incompatibility between bundle and imager
  # Extracted via: crane export ghcr.io/siderolabs/extensions:v1.12.0-beta.1 | tar -x -O image-digests
  install_system_extensions = [
    "ghcr.io/siderolabs/i915:20251125-v1.12.0-beta.1@sha256:53ea16f2903eb6c22e9bb06299c01335cefaa4e323b8d15d8f390ceec93bb1f4",
    "ghcr.io/siderolabs/qemu-guest-agent:10.1.2@sha256:b08ff5670b5062e403a2a9ae2ab52b0429bba0075022fbe46837b4b509cf5724",
    # Container runtimes
    "ghcr.io/siderolabs/crun:1.18.2@sha256:41da007fe45ea9083dd67b8cfb15596ce50f23ea3f2e2e8a72530b071a1b1c47",
    "ghcr.io/siderolabs/ctr:1.7.23@sha256:d3e2a09c8a41b8ad6a1a5903e62ffd9eb0e2c5e89b4a8f3af26d92d96a61bf93",
    # BIRD2 extension for BGP routing (official siderolabs extension)
    "ghcr.io/siderolabs/bird2:2.17.1@sha256:df43cff2b97087a0bd03d10bf8a13363ea19bfe44c18309f40b1e009793b56bf",
  ]

  # Custom third-party extensions
  # COMMENTED OUT: FRR extension (replaced by BIRD2)
  # To rollback to FRR, uncomment the line below and remove BIRD2 from install_system_extensions
  install_custom_extensions = [
    # "ghcr.io/sulibot/frr-talos-extension:v1.0.15",
  ]
}
