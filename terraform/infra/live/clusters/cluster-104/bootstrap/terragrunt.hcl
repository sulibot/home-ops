# Thin wrapper: all real configuration lives in the shared unit template.
# Cluster-specific values come from ../cluster.hcl, which the template reads.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "unit" {
  path           = "${get_terragrunt_dir()}/../../_shared/units/bootstrap.hcl"
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

# Metal-cluster extras on top of the shared template (deep-merged).
inputs = {
  cluster_name     = local.cluster_config.cluster_name
  output_directory = "${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}"
}
