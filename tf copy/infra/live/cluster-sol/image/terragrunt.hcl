include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/talos_proxmox_image"
}

locals {
  cluster       = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  globals       = read_terragrunt_config(find_in_parent_folders("globals.hcl")).locals
  image_opts    = read_terragrunt_config(find_in_parent_folders("image.hcl")).locals
  nodes_inputs  = read_terragrunt_config(find_in_parent_folders("nodes.hcl")).inputs
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  default_version  = try(local.cluster.talos_version, local.globals.talos_version, "v1.8.2")
  file_name_prefix = format("%s%d", local.cluster.cluster_name, local.cluster.cluster_id)
  # Upload Talos image to local storage on pve01 only (RBD doesn't support file uploads)
  datastore_id     = "local"
  upload_nodes     = ["pve01"]

  extra_kernel_args = try(local.image_opts.talos_extra_kernel_args, [])
  system_extensions = try(local.image_opts.talos_system_extensions, [])
  talos_patches     = try(local.image_opts.talos_patches, [])
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
}
