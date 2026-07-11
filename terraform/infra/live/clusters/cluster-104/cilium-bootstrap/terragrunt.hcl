# Thin wrapper: all real configuration lives in the shared unit template.
# Cluster-specific values come from ../cluster.hcl, which the template reads.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "unit" {
  path           = "${get_terragrunt_dir()}/../../_shared/units/cilium-bootstrap.hcl"
  merge_strategy = "deep"
  expose         = true
}

# Terragrunt does not merge exclude blocks from included files, so the block
# lives here; the condition itself is computed in the shared template.
exclude {
  if      = include.unit.locals.exclude_unit
  actions = ["all"]
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
}

# Metal-cluster extras on top of the shared template (deep-merged): single
# node, native routing on the node's own VLAN interface.
inputs = {
  direct_routing_device    = values(local.cluster_config.nodes)[0].interface
  ipv4_native_routing_cidr = "10.${local.cluster_config.cluster_id}.0.0/16"
  ipv6_native_routing_cidr = "fd00:${local.cluster_config.cluster_id}::/48"
  operator_replicas        = 1
}
