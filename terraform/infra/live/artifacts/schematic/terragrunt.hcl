# Generate Talos Image Factory schematic ID from official extensions
# This schematic ID can be used to download installer images and ISOs from factory.talos.dev
# All extensions are now official Siderolabs extensions (no custom builds needed)

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/talos_install_schematic"

  after_hook "write_artifact_schematic_catalog" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -euo pipefail

      CATALOG_PATH="${get_repo_root()}/terraform/infra/live/clusters/_shared/artifacts-schematic.json"
      NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      mkdir -p "$(dirname "$CATALOG_PATH")"

      tofu output -json | jq --arg generated_at "$NOW" '{
        schematic_id: .schematic_id.value,
        generated_at: $generated_at
      }' > "$CATALOG_PATH"

      echo "✓ Wrote artifact schematic catalog: $CATALOG_PATH"
    EOT
    ]
    run_on_error = false
  }
}

locals {
  versions          = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
}

inputs = {
  # Kernel arguments for UKI (Unified Kernel Image)
  talos_extra_kernel_args = local.install_schematic.install_kernel_args

  # Official Siderolabs extensions (factory format: siderolabs/extension-name)
  talos_system_extensions = local.install_schematic.install_factory_extensions

  # No custom extensions - bird2 is now an official Siderolabs extension
  talos_custom_extensions = []
}
