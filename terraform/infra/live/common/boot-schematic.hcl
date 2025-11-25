# Boot schematic for nocloud ISO
# Minimal extensions for Proxmox VM boot

locals {
  # Reuse kernel args from main schematic
  boot_kernel_args = read_terragrunt_config("${path_relative_to_include()}/schematic.hcl").locals.talos_extra_kernel_args

  # Minimal boot extensions - just what Proxmox needs
  boot_system_extensions = [
    "siderolabs/qemu-guest-agent"
  ]
}
