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
    "ghcr.io/siderolabs/intel-ucode:20251111@sha256:c6ed9685f0ad85b3ec98f4129ea1b75342719b94e02bbd945929eba9436a47c5",
    "ghcr.io/siderolabs/qemu-guest-agent:10.1.2@sha256:b08ff5670b5062e403a2a9ae2ab52b0429bba0075022fbe46837b4b509cf5724",
    "ghcr.io/siderolabs/util-linux-tools:2.41.2@sha256:dc9f935ea8756dba5b8b87cd92bb8950af8e201645811ec0c9ac78703336677a",
  ]

  # Custom third-party extensions
  install_custom_extensions = [
    "ghcr.io/sulibot/frr-talos-extension:v1.0.15",
  ]
}
