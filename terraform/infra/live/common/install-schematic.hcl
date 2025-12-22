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

  # Install extensions for Talos v1.11.5
  # Official Siderolabs extensions with pinned digests
  # Extracted via: crane export ghcr.io/siderolabs/extensions:v1.11.5 - | tar x -O image-digests
  install_system_extensions = [
    "ghcr.io/siderolabs/intel-ucode:20250812@sha256:31142ac037235e6779eea9f638e6399080a1f09e7c323ffa30b37488004057a5",
    "ghcr.io/siderolabs/qemu-guest-agent:10.0.2@sha256:9720300de00544eca155bc19369dfd7789d39a0e23d72837a7188f199e13dc6c",
    "ghcr.io/siderolabs/crun:1.24@sha256:157f1c563931275443dd46fbc44c854c669f5cf4bbc285356636a57c6d33caed",
    "ghcr.io/siderolabs/ctr:v2.1.5@sha256:73abe655f96bb40a02fc208bf2bed695aa02a85fcd93ff521a78bb92417652c5",
  ]

  # FRR extension from sulibot fork
  # v1.0.18: Fixed bgpd health check - restarts process instead of killing container
  # v1.0.17: Includes Prometheus metrics exporter on port 9342
  install_custom_extensions = [
    "ghcr.io/sulibot/frr-talos-extension:v1.0.18",
  ]
}
