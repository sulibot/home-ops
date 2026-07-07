terraform {
  source = "../../../modules/proxmox_ceph_pools"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "versions" {
  path = find_in_parent_folders("common/versions.hcl")
}

include "credentials" {
  path = find_in_parent_folders("common/credentials.hcl")
}

locals {
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  ceph_catalog  = read_terragrunt_config(find_in_parent_folders("common/proxmox-ceph-pools.hcl")).locals
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  username = "root@pam"
  password = data.sops_file.proxmox.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
EOF
}

inputs = {
  node_name  = local.proxmox_infra.proxmox_primary_node
  ceph_pools = local.ceph_catalog.ceph_pools
}
