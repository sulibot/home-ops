include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "image" {
  config_path = "../../../artifacts/registry"

  # Provide mocks so `plan` can run without first applying the image stack.
  mock_outputs = {
    talos_image_file_ids = {
      "pve01" = "resources:iso/mock-talos-image.iso"
    }
    talos_image_file_name = "mock-talos-image.iso"
    talos_image_id        = "mock-schematic-id"
    talos_version         = "v1.11.5"
    kubernetes_version    = "v1.34.1"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/cluster_core"

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

  # Read centralized infrastructure configurations
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  ipv6_prefixes = read_terragrunt_config(find_in_parent_folders("common/ipv6-prefixes.hcl")).locals
  versions      = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals

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
    vm_id         = tonumber(format("%d0%d", local.cluster_config.cluster_id, i + local.network_infra.addressing.controlplane_offset))
    ip_suffix     = i + local.network_infra.addressing.controlplane_offset
    control_plane = true
    # Merge role-specific defaults
    cpu_cores = local.control_plane_defaults.cpu_cores
    memory_mb = local.control_plane_defaults.memory_mb
    disk_gb   = local.control_plane_defaults.disk_gb
  }]

  # Generate worker nodes
  workers = [for i in range(local.cluster_config.workers) : {
    name          = format("%swk%02d", local.cluster_config.cluster_name, i + 1)
    vm_id         = tonumber(format("%d0%d", local.cluster_config.cluster_id, i + local.network_infra.addressing.worker_offset))
    ip_suffix     = i + local.network_infra.addressing.worker_offset
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
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  # Use root credentials instead of API token for hardware mapping support
  # Hardware mappings require root PAM authentication due to IOMMU interactions
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

generate "routeros_provider" {
  path      = "routeros_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "routeros" {
      hosturl  = data.sops_file.proxmox.data["routeros_hosturl"]
      username = data.sops_file.proxmox.data["routeros_username"]
      password = data.sops_file.proxmox.data["routeros_password"]
      insecure = true
    }
  EOF
}

generate "dns" {
  path      = "dns_nodes.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    # Loopback records — {name}.${local.network_infra.base_domain} → loopback IPs (BGP-routed)
    resource "routeros_ip_dns_record" "node_loopback_aaaa" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}.${local.network_infra.base_domain}"
      type    = "AAAA"
      address = "fd00:${local.cluster_config.cluster_id}:fe::$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.cluster_config.cluster_id} compute"
    }

    resource "routeros_ip_dns_record" "node_loopback_a" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}.${local.network_infra.base_domain}"
      type    = "A"
      address = "10.${local.cluster_config.cluster_id}.254.$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.cluster_config.cluster_id} compute"
    }

    # Interface records — {name}-int.${local.network_infra.base_domain} → public VLAN IPs
    resource "routeros_ip_dns_record" "node_int_aaaa" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}-int.${local.network_infra.base_domain}"
      type    = "AAAA"
      address = "$${var.ip_config.public.ipv6_prefix}$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.cluster_config.cluster_id} compute"
    }

    resource "routeros_ip_dns_record" "node_int_a" {
      for_each = { for node in var.nodes : node.name => node }
      name    = "$${each.key}-int.${local.network_infra.base_domain}"
      type    = "A"
      address = "$${var.ip_config.public.ipv4_prefix}$${each.value.ip_suffix}"
      ttl     = "5m"
      comment = "managed by terraform cluster-${local.cluster_config.cluster_id} compute"
    }
  EOF
}

inputs = merge(
  {
    # Cluster identification
    cluster_id = local.cluster_config.cluster_id

    # Pass the generated node list and IP config to the module
    nodes = local.final_nodes

    # Use shared artifacts from dependency
    talos_image_file_id = dependency.image.outputs.talos_image_file_ids[local.proxmox_infra.proxmox_nodes[0]]
    # Get versions from centralized versions.hcl (not from image build)
    talos_version       = local.versions.talos_version
    kubernetes_version  = local.versions.kubernetes_version
    ip_config = {
      mesh = {
        ipv6_prefix  = "fc00:${local.cluster_config.cluster_id}::"
        ipv4_prefix  = "10.10.${local.cluster_config.cluster_id}."
        #ipv6_gateway = "fc00:${local.cluster_config.cluster_id}::fffe"
        #ipv4_gateway = "10.10.${local.cluster_config.cluster_id}.254"
      }
      public = {
        ipv6_prefix  = "fd00:${local.cluster_config.cluster_id}::"
        ipv4_prefix  = "10.${local.cluster_config.cluster_id}.0."
        # ULA gateway for routing to other ULA subnets (e.g., fd00:0:0:ffff::53)
        ipv6_gateway = "fd00:${local.cluster_config.cluster_id}::fffe"
        ipv4_gateway = "10.${local.cluster_config.cluster_id}.0.254"
        # GUA IPv6 gateway overrides ULA as the default route for internet
        gua_ipv6_prefix  = try(local.ipv6_prefixes.delegated_prefixes["vnet${local.cluster_config.cluster_id}"], "")
        gua_ipv6_gateway = try(local.ipv6_prefixes.delegated_gateways["vnet${local.cluster_config.cluster_id}"], "")
      }
      dns_servers = [
        local.network_infra.dns_servers.ipv6,
        local.network_infra.dns_servers.ipv4,
      ]
    }

    # Default wiring for both NICs
    network = local.cluster_config.network

    # Pass through centralized Proxmox infrastructure config
    proxmox = {
      datastore_id = local.proxmox_infra.storage.datastore_id
      vm_datastore = local.proxmox_infra.storage.vm_datastore
      node_primary = local.proxmox_infra.proxmox_primary_node
      nodes        = local.proxmox_infra.proxmox_nodes
    }

    proxmox_ssh_hostnames = local.proxmox_infra.proxmox_hostnames

    # Provide generic fallbacks for the module (all nodes already have explicit sizing)
    vm_defaults = {
      cpu_cores = local.control_plane_defaults.cpu_cores
      memory_mb = local.control_plane_defaults.memory_mb
      disk_gb   = local.worker_defaults.disk_gb
    }
  },
)
