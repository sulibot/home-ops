# Custom Talos installer with FRR extension

terraform {
  source = "${get_repo_root()}/terraform/infra/modules/talos_custom_installer"
}

include "root" {
  path   = find_in_parent_folders()
  expose = true
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
    "ghcr.io/jsenecal/frr-talos-extension:latest",
  ]

  # Registry to push the custom installer image
  # TODO: Update this with your actual registry
  output_registry = "ghcr.io/${local.cluster_config.cluster_name}/talos-installer-frr"
}
