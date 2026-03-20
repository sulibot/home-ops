# Publish Talos image to Proxmox infrastructure
# Uses Talos Image Factory + proxmox provider (no local Docker ISO build)

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/talos_proxmox_image"

  after_hook "write_artifact_registry_catalog" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -euo pipefail

      CATALOG_PATH="${get_repo_root()}/terraform/infra/live/clusters/_shared/artifacts-registry.json"
      NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      mkdir -p "$(dirname "$CATALOG_PATH")"

      tofu output -json | jq \
        --arg generated_at "$NOW" \
        --arg talos_version "${local.versions.talos_version}" \
        --arg kubernetes_version "${local.versions.kubernetes_version}" \
        '{
        talos_image_file_ids: .talos_image_file_ids.value,
        talos_image_file_name: .talos_image_file_name.value,
        talos_image_id: .talos_image_id.value,
        talos_version: $talos_version,
        kubernetes_version: $kubernetes_version,
        generated_at: $generated_at
      }' > "$CATALOG_PATH"

      echo "✓ Wrote artifact registry catalog: $CATALOG_PATH"
    EOT
    ]
    run_on_error = false
  }
}

locals {
  # Import centralized Proxmox infrastructure configuration
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  versions      = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  schematic     = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
}

inputs = {
  talos_version           = local.versions.talos_version
  talos_platform          = local.versions.talos_platform
  talos_architecture      = local.versions.talos_architecture
  talos_extra_kernel_args = local.schematic.install_kernel_args
  talos_system_extensions = local.schematic.install_factory_extensions
  talos_custom_extensions = []
  file_name_prefix        = "talos-factory"

  # Use centralized Proxmox infrastructure configuration
  proxmox_datastore_id = local.proxmox_infra.storage.datastore_id
  proxmox_node_names   = local.proxmox_infra.proxmox_nodes
}
