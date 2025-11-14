include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

# dependency "image" {
#   config_path = "../image"
#
#   # Retry up to 5 times, waiting 15s between retries, if the output is not available yet
#   mock_outputs_allowed_terraform_commands = ["plan", "validate", "show"]
# }

terraform {
  source = "../../../modules/cluster_core"
}

locals {
  # Read the high-level cluster definition from the parent folder
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals

  # Generate control plane nodes
  control_planes = [for i in range(local.cluster_config.controlplanes) : {
    name      = format("%s-cp%02d", local.cluster_config.cluster_name, i + 1)
    vm_id     = tonumber(format("%d0%d", local.cluster_config.cluster_id, i + 11))
    ip_suffix = i + 11
  }]

  # Generate worker nodes
  workers = [for i in range(local.cluster_config.workers) : {
    name      = format("%s-wk%02d", local.cluster_config.cluster_name, i + 1)
    vm_id     = tonumber(format("%d0%d", local.cluster_config.cluster_id, i + 21))
    ip_suffix = i + 21
  }]

  # Combine all nodes and apply any specific overrides
  all_nodes = concat(local.control_planes, local.workers)
  nodes_map = { for node in local.all_nodes : node.name => node }

  # Final merged list of nodes to pass to the module
  final_nodes = [
    for name, config in merge(local.nodes_map, local.cluster_config.node_overrides) :
    merge(lookup(local.nodes_map, name, {}), config)
  ]

  # Read credentials from the common file
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
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
    # Pass the generated node list and IP config to the module
    nodes               = local.final_nodes
    talos_image_file_id = "resources:iso/sol101-43738cb3ab16b5ee9c62f4bf35b23364dfa2ae8e737a481627e5c27088e17e11.iso"
    ip_config           = {
      ipv6_prefix  = "fd00:${local.cluster_config.cluster_id}::"
      ipv4_prefix  = "10.${local.cluster_config.cluster_id}.0."
      ipv6_gateway = "fd00:${local.cluster_config.cluster_id}::fffe"
      ipv4_gateway = "10.${local.cluster_config.cluster_id}.0.254"
      dns_servers  = ["fd00:${local.cluster_config.cluster_id}::fffe", "10.${local.cluster_config.cluster_id}.0.254"]
    }

    # Default wiring for both NICs
    network = local.cluster_config.network

    # Pass through other necessary variables
    proxmox = {
      datastore_id = "resources"
      vm_datastore = "rbd-vm"
      node_primary = "pve01"
      nodes        = local.cluster_config.proxmox_nodes
    }
    vm_defaults = {
      cpu_cores = 4
      memory_mb = 8192
      disk_gb   = 60
    }
  },
)
