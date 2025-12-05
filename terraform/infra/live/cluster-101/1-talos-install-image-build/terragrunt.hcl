# Custom Talos installer with FRR extension

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
}

inputs = {
  talos_version = local.versions.talos_version

  # Custom extensions to include in the installer
  custom_extensions = [
    "ghcr.io/sulibot/frr-talos-extension:latest",  # Use fork with allowas-in and enhanced monitoring
  ]

  # Registry to push the custom installer image
  # Using GitHub Container Registry (ghcr.io)
  output_registry = "ghcr.io/sulibot/${local.cluster_config.cluster_name}-talos-installer-frr"
}
