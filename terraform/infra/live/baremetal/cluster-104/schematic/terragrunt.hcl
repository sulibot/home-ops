# Generate the bare-metal Talos Image Factory schematic for cluster-104.
# Unlike the shared VM-oriented schematic, this intentionally excludes
# qemu-guest-agent because talos01 is physical hardware.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/talos_install_schematic"

  after_hook "write_cluster_schematic_catalog" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -euo pipefail

      CATALOG_PATH="${get_terragrunt_dir()}/schematic.json"
      NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

      tofu output -json | jq --arg generated_at "$NOW" '{
        schematic_id: .schematic_id.value,
        generated_at: $generated_at,
        scope: "cluster-104-baremetal"
      }' > "$CATALOG_PATH"

      echo "✓ Wrote cluster-104 bare-metal schematic catalog: $CATALOG_PATH"
    EOT
    ]
    run_on_error = false
  }
}

locals {
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals

  baremetal_factory_extensions = [
    for extension in local.install_schematic.install_factory_extensions :
    extension if !strcontains(extension, "qemu-guest-agent")
  ]
}

inputs = {
  talos_extra_kernel_args = local.install_schematic.install_kernel_args
  talos_system_extensions = local.baremetal_factory_extensions
  talos_custom_extensions = []
}
