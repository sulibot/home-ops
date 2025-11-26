# Boot schematic for nocloud ISO
# Minimal configuration for Proxmox VM boot

locals {
  # Minimal kernel args for boot (empty - use defaults)
  boot_kernel_args = []

  # Minimal boot extensions - just what Proxmox needs
  boot_system_extensions = [
    "siderolabs/qemu-guest-agent"
  ]
}
