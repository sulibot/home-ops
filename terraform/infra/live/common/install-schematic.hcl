# Install schematic for actual system
# Full configuration with all kernel args and extensions

locals {
  # Pull versions so we can tag extensions correctly
  # Explicit path so it works from .terragrunt-cache during run-all
  versions = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/versions.hcl").locals

  # Kernel args for production system (metal platform)
  install_kernel_args = [
    "console=ttyS0,115200",  # Serial console output (VGA is none on GPU passthrough nodes)
    # NOTE: talos.platform is NOT set here — imager --platform metal/nocloud sets it
    # per-image.  Setting it here would override nocloud platform on the boot ISO
    # and break cloud-init (nodes would never get static IPs).
    "-init_on_alloc",        # Less security, faster performance
    "-init_on_free",         # Less security, faster performance
    "-selinux",              # Less security, faster performance
    "apparmor=0",            # Less security, faster performance
    # Xe driver for SR-IOV VF support (official Siderolabs extension)
    "xe.force_probe=4680",   # Enable Xe for Alder Lake-S GT1 VF (from Proxmox SR-IOV)
    "init_on_alloc=0",       # Less security, faster performance
    "init_on_free=0",        # Less security, faster performance
    "intel_iommu=on",        # PCI Passthrough
    "iommu=pt",              # PCI Passthrough
    "mitigations=off",       # Less security, faster performance
    "module_blacklist=igc",  # Disable onboard NIC
    "module.sig_enforce=0",  # Allow unsigned kernel modules (keeping for flexibility)
    "security=none",         # Less security, faster performance
    "sysctl.kernel.kexec_load_disabled=1",  # Meteor Lake CPU & Intel iGPU
    "talos.auditd.disabled=1",  # Less security, faster performanceu.ol80
  ]

  # All official Siderolabs extensions with pinned digests
  # Extracted via: crane export ghcr.io/siderolabs/extensions:v1.12.4 - | tar x -O image-digests
  install_system_extensions = [
    "ghcr.io/siderolabs/xe:20260110-v1.12.4@sha256:cdebb42c0a38376adaae7101c46ae3a3fc988cfedc6585dd913bf866b7d04c4a",
    "ghcr.io/siderolabs/qemu-guest-agent:10.2.0@sha256:ae6ca226e7b66abdd072780408fc24b554c7c41fd2397826cf85a301133a776e",
    "ghcr.io/siderolabs/crun:1.26@sha256:1a4da9e528d92f6e9ff415d020650272d7a3e5c6b84a5c60e1aa19de62ac77bf",
    "ghcr.io/siderolabs/ctr:v2.1.6@sha256:fc7070c8960415c0dfd8bd3ccd9df813b31d353278be378b54cc4d6933ea23ea",
    # bird2 BGP daemon for simplified BGP configuration - replaces custom FRR extension
    "ghcr.io/siderolabs/bird2:2.18@sha256:851863979fda30005e74f17d018de5103d1618258684dbcdf81933bfae919490",
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
