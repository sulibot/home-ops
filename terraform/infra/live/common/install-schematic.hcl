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
    "i915.disable_display=1",  # Disable display subsystem for compute-only (Plex transcoding)
    "i915.enable_guc=0",     # Disable GuC firmware loading (fixes VM boot hang)
    "i915.force_probe=4680", # Force enable Alder Lake iGPU support
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

  # Install extensions for Talos v1.12.1
  # Official Siderolabs extensions with pinned digests
  # Extracted via: crane export ghcr.io/siderolabs/extensions:v1.12.1 - | tar x -O image-digests
  install_system_extensions = [
    "ghcr.io/siderolabs/i915:20251125-v1.12.1@sha256:fb89c85a04ecb85abaec9d400e03a1628bf68aef3580e98f340cbe8920a6e4ed",
    "ghcr.io/siderolabs/qemu-guest-agent:10.2.0@sha256:b2843f69e3cd31ba813c1164f290ebbfddd239d53b3a0eeb19eb2f91fec6fed7",
    "ghcr.io/siderolabs/crun:1.26@sha256:5910e8e068a557afd727344649e0e6738ba53267c4339213924d4349567fe8d4",
    "ghcr.io/siderolabs/ctr:v2.1.5@sha256:67337f841b2ad13fbf43990e735bc9e61deafb91ab5d4fde42392b49f58cbe00",
  ]

  # FRR extension from sulibot fork
  # v1.0.25: Make BGP prefsrc optional to avoid route install failures.
  # v1.0.23: Fix Cilium neighbor address selection; guard BFD rendering when undefined.
  # v1.0.20: Guard BFD config rendering when bfd is omitted.
  # v1.0.19: config.yaml + veth/netns Cilium peering; FRR 10.5.1
  # v1.0.18: Fixed bgpd health check - restarts process instead of killing container
  # v1.0.17: Includes Prometheus metrics exporter on port 9342
  install_custom_extensions = [
    "ghcr.io/sulibot/frr-talos-extension:v1.0.25",
  ]
}
