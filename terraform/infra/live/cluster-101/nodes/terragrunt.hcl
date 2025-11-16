include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

dependency "image" {
  config_path = "../image"

  # Provide mocks so `plan` can run without first applying the image stack.
  mock_outputs = {
    talos_image_file_ids = {
      "pve01" = "resources:iso/mock-talos-image.iso"
    }
    talos_image_file_name = "mock-talos-image.iso"
    talos_image_id        = "mock-schematic-id"
    talos_version         = "v1.8.2"
    kubernetes_version    = "v1.31.4"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

terraform {
  source = "../../../modules/cluster_core"

  # Automatically generate talenv.yaml after successful apply
  after_hook "generate_talenv" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "cd ${get_repo_root()} && mkdir -p talos/clusters/cluster-${local.cluster_config.cluster_id} && cd ${get_terragrunt_dir()} && terragrunt output -raw talenv_yaml 2>/dev/null | yq eval '... style=\"\"' - > ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/talenv.yaml"]
    run_on_error = false
  }
}

locals {
  # Read the high-level cluster definition from the parent folder
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals

  # Define role-based hardware defaults
  control_plane_defaults = {
    cpu_cores = 4
    memory_mb = 8192
    disk_gb   = 40 # Smaller disk for CP nodes
  }
  worker_defaults = {
    cpu_cores = 6
    memory_mb = 16384
    disk_gb   = 80 # Larger disk for worker nodes
  }

  # Generate control plane nodes
  control_planes = [for i in range(local.cluster_config.controlplanes) : {
    name          = format("%scp%02d", local.cluster_config.cluster_name, i + 1)
    vm_id         = tonumber(format("%d0%d", local.cluster_config.cluster_id, i + 11))
    ip_suffix     = i + 11
    control_plane = true
    # Merge role-specific defaults
    cpu_cores = local.control_plane_defaults.cpu_cores
    memory_mb = local.control_plane_defaults.memory_mb
    disk_gb   = local.control_plane_defaults.disk_gb
  }]

  # Generate worker nodes
  workers = [for i in range(local.cluster_config.workers) : {
    name          = format("%swk%02d", local.cluster_config.cluster_name, i + 1)
    vm_id         = tonumber(format("%d0%d", local.cluster_config.cluster_id, i + 21))
    ip_suffix     = i + 21
    control_plane = false
    # Merge role-specific defaults
    cpu_cores = local.worker_defaults.cpu_cores
    memory_mb = local.worker_defaults.memory_mb
    disk_gb   = local.worker_defaults.disk_gb
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
    # Cluster identification
    cluster_id = local.cluster_config.cluster_id

    # Pass the generated node list and IP config to the module
    nodes = local.final_nodes
    # Dynamically get the image ID from the 'image' module dependency.
    # This assumes the image is uploaded to the primary proxmox node.
    talos_image_file_id = dependency.image.outputs.talos_image_file_ids[local.cluster_config.proxmox_nodes[0]]
    talos_version       = dependency.image.outputs.talos_version
    kubernetes_version  = dependency.image.outputs.kubernetes_version
    ip_config = {
      mesh = {
        ipv6_prefix  = "fc00:${local.cluster_config.cluster_id}::"
        ipv4_prefix  = "10.10.${local.cluster_config.cluster_id}."
        #ipv6_gateway = "fc00:${local.cluster_config.cluster_id}::fffe"
        #ipv4_gateway = "10.10.${local.cluster_config.cluster_id}.254"
      }
      public = {
        ipv6_prefix  = "fd00:${local.cluster_config.cluster_id}::"
        ipv4_prefix  = "10.0.${local.cluster_config.cluster_id}."
        #ipv6_gateway = "fd00:${local.cluster_config.cluster_id}::fffe"
        ipv4_gateway = "10.0.${local.cluster_config.cluster_id}.254"
      }
      dns_servers = [
        "fd00:${local.cluster_config.cluster_id}::fffe",
        "10.0.${local.cluster_config.cluster_id}.254",
      ]
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

    # Provide generic fallbacks for the module (all nodes already have explicit sizing)
    vm_defaults = {
      cpu_cores = local.control_plane_defaults.cpu_cores
      memory_mb = local.control_plane_defaults.memory_mb
      disk_gb   = local.worker_defaults.disk_gb
    }
  },
)
