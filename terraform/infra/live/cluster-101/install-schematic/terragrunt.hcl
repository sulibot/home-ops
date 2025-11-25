include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/talos_install_schematic"
}

locals {
  # Read install schematic for full extensions
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
}

inputs = {
  talos_extra_kernel_args = local.install_schematic.install_kernel_args
  talos_system_extensions = local.install_schematic.install_system_extensions
}
