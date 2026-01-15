terraform {
  source = "../../../modules/proxmox_sdn"
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

include "ipv6_prefixes" {
  path   = find_in_parent_folders("common/ipv6-prefixes.hcl")
  expose = true
}

locals {
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  # Import centralized infrastructure configurations
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  vnets_config  = read_terragrunt_config(find_in_parent_folders("common/sdn-vnets.hcl")).locals

  # Import delegated prefixes and transform to module format
  ipv6_config      = include.ipv6_prefixes.locals
  delegated_prefixes = {
    for vnet, prefix in local.ipv6_config.delegated_prefixes :
    vnet => {
      prefix  = prefix
      gateway = local.ipv6_config.delegated_gateways[vnet]
    }
  }
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

# SDN configuration must be applied after FRR EVPN is configured via Ansible
# This dependency is informational - Ansible must be run manually first
# dependency "frr_config" {
#   config_path = "../../ansible-applied"  # Placeholder
#   mock_outputs_allowed_terraform_commands = ["validate", "plan"]
#   mock_outputs = {
#     ready = true
#   }
# }

inputs = {
  # Use centralized SDN configuration
  zone_id           = local.network_infra.sdn.zone_id
  vrf_vxlan         = local.network_infra.sdn.vrf_vxlan
  mtu               = local.network_infra.sdn.mtu
  disable_arp_nd_suppression = local.network_infra.sdn.disable_arp_nd_suppression
  advertise_subnets          = local.network_infra.sdn.advertise_subnets

  # Use centralized Proxmox cluster configuration
  nodes             = local.proxmox_infra.proxmox_nodes
  exit_nodes        = local.proxmox_infra.proxmox_nodes
  primary_exit_node = local.proxmox_infra.proxmox_primary_node

  # Route target for importing default route from RouterOS into VRF
  rt_import = "65000:1"

  # VNets dynamically generated from centralized cluster list
  vnets = {
    for vnet_name, vnet_config in local.vnets_config.vnets : vnet_name => {
      alias      = "Talos Cluster ${replace(vnet_name, "vnet", "")}"
      vxlan_id   = vnet_config.vxlan_id
      subnet     = vnet_config.ipv6_subnet
      gateway    = vnet_config.ipv6_gateway
      subnet_v4  = vnet_config.ipv4_subnet
      gateway_v4 = vnet_config.ipv4_gateway
    }
  }

  # Use AT&T delegated GUA prefixes directly on VNets
  delegated_prefixes = local.delegated_prefixes
}
