# Build all Talos image formats
# - Installer image (metal platform) → container registry
# - Boot ISO (nocloud platform) → local file system
# Both use identical extensions and configuration

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# NOTE: Extension build step exists at ../extension/ but is optional
# The FRR extension is pre-built and available at ghcr.io/sulibot/frr-talos-extension:v1.0.30
# Only rebuild extension when the FRR extension code itself changes

terraform {
  source = "../../../modules/talos_images"
}

locals {
  versions          = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
}

inputs = {
  talos_version      = local.versions.talos_version
  kubernetes_version = local.versions.kubernetes_version

  # System extensions (official Siderolabs + custom FRR)
  official_extensions = local.install_schematic.install_system_extensions
  custom_extensions   = local.install_schematic.install_custom_extensions

  # Kernel arguments
  kernel_args = local.install_schematic.install_kernel_args

  # Output: Installer image (pushed to registry) - version-based, not cluster-specific
  installer_registry = "ghcr.io/sulibot/talos-frr-installer"

  # Output: Boot ISO (written to local filesystem) - version-based, not cluster-specific
  iso_output_dir = "${get_repo_root()}/build/talos-iso"
  iso_name       = "talos-frr-${local.versions.talos_version}-nocloud-amd64.iso"
}
