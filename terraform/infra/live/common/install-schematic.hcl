# Install schematic for actual system
# Full set of extensions minus cloudflared

locals {
  # Reuse kernel args from shared schematic
  install_kernel_args = read_terragrunt_config("${path_relative_to_include()}/shared-schematic.hcl").locals.talos_extra_kernel_args

  # Full install extensions (minus cloudflared)
  install_system_extensions = [
    "siderolabs/i915",
    "siderolabs/intel-ucode",
    "siderolabs/qemu-guest-agent",
    "siderolabs/util-linux-tools",
    "siderolabs/zfs",
    "siderolabs/nfsd",
    "siderolabs/nfsrahead",
  ]

  # Custom extensions
  install_custom_extensions = [
    "ghcr.io/jsenecal/frr-talos-extension:latest",
  ]
}
