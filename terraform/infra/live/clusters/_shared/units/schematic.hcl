# Shared unit template: schematic (bare-metal provisioning; VM clusters use compute)
# Generates the bare-metal Talos Image Factory schematic for a metal cluster.
# Unlike the shared VM-oriented schematic, this intentionally excludes
# qemu-guest-agent because the nodes are physical hardware. The generated
# schematic.json lands in the including unit's directory, where the sibling
# config-metal unit reads it.

locals {
  cluster_config    = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  cluster_id        = local.cluster_config.cluster_id
  tenant_id         = local.cluster_config.tenant_id
  cluster_enabled   = try(local.cluster_config.enabled, true)
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals

  baremetal_factory_extensions = [
    for extension in local.install_schematic.install_factory_extensions :
    extension if !strcontains(extension, "qemu-guest-agent")
  ]

  # Condition consumed by the child stub's exclude block. Terragrunt does
  # not merge exclude blocks from included files, so the stub declares the
  # block and reads this condition via include.unit.locals.exclude_unit.
  exclude_unit = !local.cluster_enabled
}

terraform {
  source = "${get_repo_root()}/terraform/infra/modules/talos_install_schematic"

  before_hook "enforce_cluster_enabled" {
    commands = ["init", "validate", "plan", "apply", "destroy", "refresh", "import", "output", "state", "console"]
    execute = ["bash", "-c", "if [ \"${local.cluster_enabled}\" != \"true\" ]; then echo 'ERROR: cluster-${local.tenant_id} is disabled (enabled=false in cluster.hcl). This module is excluded from run-all by design; refusing a direct single-unit command here too. Set enabled=true first if this is intentional.' >&2; exit 1; fi"]
  }

  after_hook "write_cluster_schematic_catalog" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -euo pipefail

      CATALOG_PATH="${get_terragrunt_dir()}/schematic.json"
      NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

      tofu output -json | jq --arg generated_at "$NOW" '{
        schematic_id: .schematic_id.value,
        generated_at: $generated_at,
        scope: "cluster-${local.cluster_id}-baremetal"
      }' > "$CATALOG_PATH"

      echo "✓ Wrote cluster-${local.cluster_id} bare-metal schematic catalog: $CATALOG_PATH"
    EOT
    ]
    run_on_error = false
  }
}

inputs = {
  talos_extra_kernel_args = local.install_schematic.install_kernel_args
  talos_system_extensions = local.baremetal_factory_extensions
  talos_custom_extensions = []
}
