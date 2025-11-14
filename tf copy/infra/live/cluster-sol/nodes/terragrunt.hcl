include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/cluster_core"
}

dependency "template" {
  config_path = "../template"

  mock_outputs = {
    template_vmid = 101000
    template_name = "talos-sol-template"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

locals {
  cluster      = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  nodes_data   = read_terragrunt_config(find_in_parent_folders("nodes.hcl")).inputs
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
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

inputs = merge(
  {
    cluster_name        = local.cluster.cluster_name
    cluster_id          = local.cluster.cluster_id
    proxmox_nodes       = local.cluster.proxmox_nodes
    storage_default     = local.cluster.storage_default
    talos_template_vmid = dependency.template.outputs.template_vmid
  },
  local.nodes_data
)
