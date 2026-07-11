# Thin wrapper: all real configuration lives in the shared unit template.
# Cluster-specific values come from ../cluster.hcl, which the template reads.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "unit" {
  path           = "${get_terragrunt_dir()}/../../_shared/units/compute.hcl"
  merge_strategy = "deep"
  expose         = true
}

# Terragrunt does not merge exclude blocks from included files, so the block
# lives here; the condition itself is computed in the shared template.
exclude {
  if      = include.unit.locals.exclude_unit
  actions = ["all"]
}
