# Install schematic for actual system
# Full configuration with all kernel args and extensions

locals {
  # Pull versions so we can tag extensions correctly
  # Explicit path so it works from .terragrunt-cache during run-all
  versions = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/versions.hcl").locals

  # Kernel args for production system (metal platform)
  install_kernel_args = [
    "console=ttyS0,115200", # Serial console output (VGA is none on GPU passthrough nodes)
    # NOTE: talos.platform is NOT set here — imager --platform metal/nocloud sets it
    # per-image.  Setting it here would override nocloud platform on the boot ISO
    # and break cloud-init (nodes would never get static IPs).
    "-init_on_alloc", # Less security, faster performance
    "-init_on_free",  # Less security, faster performance
    "-selinux",       # Less security, faster performance
    "apparmor=0",     # Less security, faster performance
    # Xe driver for SR-IOV VF support (official Siderolabs extension)
    "xe.force_probe=4680",                 # Enable Xe for Alder Lake-S GT1 VF (from Proxmox SR-IOV)
    "init_on_alloc=0",                     # Less security, faster performance
    "init_on_free=0",                      # Less security, faster performance
    "intel_iommu=on",                      # PCI Passthrough
    "iommu=pt",                            # PCI Passthrough
    "mitigations=off",                     # Less security, faster performance
    "module_blacklist=igc",                # Disable onboard NIC
    "security=none",                       # Less security, faster performance
    "sysctl.kernel.kexec_load_disabled=1", # Meteor Lake CPU & Intel iGPU
    "talos.auditd.disabled=1",             # Less security, faster performanceu.ol80
  ]

  # All official Siderolabs extensions with pinned digests
  # Extracted via: crane export ghcr.io/siderolabs/extensions:v1.14.1 - | tar x -O image-digests
  install_system_extensions = [
    "ghcr.io/siderolabs/xe:20260810-v1.14.1@sha256:4fe9687410b68dbf11ebc0baec4018c3e77b94544cb869a5d0e71c25b5715764",
    "ghcr.io/siderolabs/qemu-guest-agent:11.1.1@sha256:d63a9695bdc35b6f191223d75c605f14a4e33cb7e6c2b953370efcf02d4df84d",
    "ghcr.io/siderolabs/crun:1.29.1@sha256:094d52b22e384670d326bbdff0deb655aabc97c8520df8436e3ad27c2902d69f",
    "ghcr.io/siderolabs/ctr:v2.3.5@sha256:87476c24411b18c96f2b350153bdcc8e2c0d8a716ccd8b117997623dd820b60b",
    # bird2 BGP daemon for simplified BGP configuration - replaces custom FRR extension
    "ghcr.io/siderolabs/bird2:2.18@sha256:159778218c9293388805ab3a5005f8c55d37530b1e6a1cbb66c6c79cc3084558",
  ]

  # No custom extensions - all extensions are now official Siderolabs extensions
  install_custom_extensions = []

  # Extension names for Talos Image Factory schematic API
  # Format: siderolabs/extension-name (no version, no digest)
  # See: https://www.talos.dev/v1.11/learn-more/image-factory/
  install_factory_extensions = [
    "siderolabs/xe",
    "siderolabs/qemu-guest-agent",
    "siderolabs/crun",
    "siderolabs/ctr",
    "siderolabs/bird2",
  ]
}
