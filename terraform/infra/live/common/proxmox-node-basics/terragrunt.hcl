terraform {
  source = "../../../modules/proxmox_node_basics"
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
  credentials    = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file   = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  proxmox_infra  = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  proxmox_nodes  = local.proxmox_infra.proxmox_nodes
  managed_notice = "Managed API-level metadata only. Host OS, network, FRR, packages, and Ceph OSD workflows remain Ansible-owned."
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
}
EOF
}

inputs = {
  nodes = {
    for node in local.proxmox_nodes : node => {
      description = local.managed_notice
    }
  }
}
