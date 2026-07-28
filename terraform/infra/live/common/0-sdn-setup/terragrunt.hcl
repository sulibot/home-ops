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
  ipv6_config = include.ipv6_prefixes.locals
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
  zone_id                    = local.network_infra.sdn.zone_id
  vrf_vxlan                  = local.network_infra.sdn.vrf_vxlan
  mtu                        = local.network_infra.sdn.mtu
  disable_arp_nd_suppression = local.network_infra.sdn.disable_arp_nd_suppression
  advertise_subnets          = local.network_infra.sdn.advertise_subnets

  # Use centralized Proxmox cluster configuration
  nodes             = local.proxmox_infra.proxmox_nodes
  exit_nodes        = local.proxmox_infra.proxmox_nodes
  primary_exit_node = local.proxmox_infra.proxmox_primary_node

  # Route target for importing default route from RouterOS into VRF
  rt_import = "65000:1"

  # Push the new fabric resources live (SDN apply). Existing zone/vnet/subnet
  # state has no other pending changes, so this apply is scoped to the fabric.
  apply_sdn_config = true

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

  # ENG-325: no VNet-facing GUA subnets. Attaching a GUA subnet to a VNet
  # makes Proxmox SDN's dnsmasq send Router Advertisements for it to every
  # VM on that VNet, unconditionally - there's no way to keep the subnet
  # without the RA. That's what let VM interfaces auto-configure a GUA via
  # SLAAC even after every node-side mitigation (gua_prefix="", disabling
  # accept_ra/autoconf via machine.sysctls - which still loses the boot-time
  # race against the very first RA on some reboots; extraKernelArgs turned
  # out to be silently ignored on this Talos version's UEFI/UKI install
  # path). Removing the subnet stops the RA at its source instead of
  # fighting it node-side. NAT66 egress is unaffected - it uses the PVE
  # host's own vmbr0.10 GUA (ansible-managed SLAAC, a separate physical
  # VLAN interface, not this SDN VNet) per ENG-322/324/325.
  delegated_prefixes = {}

  # OSPF underlay fabric (see [[project ticket]] for cutover plan).
  # All three PVE hosts now managed via PVE SDN Fabrics instead of
  # hand-rolled frr.conf.local OSPF stanzas for the mesh links.
  enable_underlay_fabric = true
  fabric_nodes = {
    pve01 = { ip = "10.255.0.1", interface_names = ["enp1s0f0np0", "enp1s0f1np1"] }
    pve02 = { ip = "10.255.0.2", interface_names = ["enp1s0f0np0", "enp1s0f1np1"] }
    pve03 = { ip = "10.255.0.3", interface_names = ["enp1s0f0np0", "enp1s0f1np1"] }
  }
}
