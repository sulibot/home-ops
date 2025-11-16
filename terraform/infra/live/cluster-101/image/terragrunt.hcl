include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  # Point to the talos_proxmox_image module
  source = "../../../modules/talos_proxmox_image"
}

locals {
  cluster       = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  globals       = read_terragrunt_config(find_in_parent_folders("globals.hcl")).locals
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  # Read common schematic defaults
  common_schematic = read_terragrunt_config(find_in_parent_folders("common/schematic.hcl")).locals

  # Try to read cluster-specific overrides, fall back to empty map if no overrides
  cluster_image_opts = try(read_terragrunt_config(find_in_parent_folders("image.hcl")).locals, {})

  default_version  = try(local.cluster.talos_version, local.globals.talos_version, "v1.8.2")
  file_name_prefix = format("%s%d", local.cluster.cluster_name, local.cluster.cluster_id)
  # Upload the image to only one node to avoid disk space/network timeout issues
  datastore_id     = "resources"
  upload_nodes     = [local.cluster.proxmox_nodes[0]]  # Only upload to first node

  # Use cluster-specific overrides if defined, otherwise use common defaults
  extra_kernel_args = try(local.cluster_image_opts.talos_extra_kernel_args, local.common_schematic.talos_extra_kernel_args)
  system_extensions = try(local.cluster_image_opts.talos_system_extensions, local.common_schematic.talos_system_extensions)
  talos_patches     = try(local.cluster_image_opts.talos_patches, local.common_schematic.talos_patches)
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint  = data.sops_file.proxmox.data["pve_endpoint"]
  api_token = "$${data.sops_file.proxmox.data["pve_api_token_id"]}=$${data.sops_file.proxmox.data["pve_api_token_secret"]}"
  insecure  = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
EOF
}

inputs = {
  talos_version            = local.default_version
  talos_platform           = try(local.globals.talos_platform, "nocloud")
  talos_architecture       = try(local.globals.talos_architecture, "amd64")
  talos_extra_kernel_args  = local.extra_kernel_args
  talos_system_extensions  = local.system_extensions
  talos_patches            = local.talos_patches
  proxmox_datastore_id     = local.datastore_id
  proxmox_node_names       = local.upload_nodes
  file_name_prefix         = local.file_name_prefix
  image_cache_dir          = local.globals.image_cache_dir
}
