locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id
  context        = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals

  cluster_enabled = try(local.cluster_config.enabled, true)

  terragrunt_command_env = lower(trimspace(get_env("TERRAGRUNT_COMMAND", "")))
  terragrunt_command     = local.terragrunt_command_env != "" ? local.terragrunt_command_env : lower(trimspace(get_env("TG_COMMAND", "")))

  # Skip on destroy unless explicitly requested
  destroy_secrets = get_env("TALOS_DESTROY_SECRETS", "") != ""
  skip_destroy    = can(regex("destroy", local.terragrunt_command)) && !local.destroy_secrets

  # Skip on apply/plan unless explicitly requested to regenerate
  regenerate_secrets = get_env("TALOS_REGENERATE_SECRETS", "") != ""
  skip_apply         = can(regex("apply|plan", local.terragrunt_command)) && !local.regenerate_secrets
}

# Skip secrets module unless explicitly requested
# - On destroy: skip unless TALOS_DESTROY_SECRETS=1
# - On apply/plan: skip unless TALOS_REGENERATE_SECRETS=1
skip = !local.cluster_enabled || local.skip_destroy || local.skip_apply

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/talos_secrets"

  # Export and encrypt cluster secrets for reuse
  after_hook "export_secrets" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -e
      cd ${get_repo_root()}
      mkdir -p talos/clusters/cluster-${local.tenant_id}
      cd ${get_terragrunt_dir()}

      terragrunt output -raw secrets_yaml > \
        ${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/secrets.sops.yaml

      sops -e -i ${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/secrets.sops.yaml

      echo "✓ Exported and encrypted secrets.sops.yaml"
    EOT
    ]
    run_on_error = false
  }
}

inputs = {
  talos_version = local.context.versions.talos_version
}
