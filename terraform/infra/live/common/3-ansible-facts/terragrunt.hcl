terraform {
  source = "../../../modules/ansible_facts"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "versions" {
  path = find_in_parent_folders("common/versions.hcl")
}

locals {
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
}

inputs = {
  repo_root      = get_repo_root()
  bgp_asn_base   = local.network_infra.bgp.asn_base
  bgp_remote_asn = local.network_infra.bgp.remote_asn
  sdn_mtu        = local.network_infra.sdn.mtu
  sdn_vrf_vxlan  = local.network_infra.sdn.vrf_vxlan
  sdn_zone_id    = local.network_infra.sdn.zone_id
  routeros       = local.network_infra.routeros
}
