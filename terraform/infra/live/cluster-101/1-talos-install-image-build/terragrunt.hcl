# Custom Talos installer with BIRD2 extension

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/talos_custom_installer"
}

locals {
  # Read common configurations
  versions = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
}

inputs = {
  talos_version = local.versions.talos_version

  # Official (siderolabs) extensions baked into the installer
  official_extensions = local.install_schematic.install_system_extensions

  # Custom extensions to include in the installer
  custom_extensions = local.install_schematic.install_custom_extensions

  # Registry to push the custom installer image
  # Using GitHub Container Registry (ghcr.io)
  output_registry = "ghcr.io/sulibot/${local.cluster_config.cluster_name}-talos-installer-bird2"
}
