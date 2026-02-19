# DEPRECATED: This module builds custom Talos images with extensions
# NOW USING: Talos Image Factory (see ../schematic/)
#
# This module is kept for reference but should not be used for new clusters.
# All extensions are now official Siderolabs extensions and can be loaded
# directly from factory.talos.dev using a schematic ID.
#
# Historical purpose:
# - Built custom installer image (metal platform) → container registry
# - Built custom boot ISO (nocloud platform) → local file system

include "root" {
  path = find_in_parent_folders("root.hcl")
}

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

  # All official Siderolabs extensions (no custom extensions)
  official_extensions = local.install_schematic.install_system_extensions
  custom_extensions   = local.install_schematic.install_custom_extensions  # Now empty

  # Kernel arguments
  kernel_args = local.install_schematic.install_kernel_args

  # Output: Installer image (pushed to registry) - version-based, not cluster-specific
  installer_registry = "ghcr.io/sulibot/talos-frr-installer"

  # Output: Boot ISO (written to local filesystem) - version-based, not cluster-specific
  iso_output_dir = "${get_repo_root()}/build/talos-iso"
  iso_name       = "talos-frr-${local.versions.talos_version}-nocloud-amd64.iso"
}
