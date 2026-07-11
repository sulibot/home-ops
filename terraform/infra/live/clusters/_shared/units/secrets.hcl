# Shared unit template: secrets
# Included by each cluster's secrets/terragrunt.hcl. All cluster-specific values
# come from that cluster's cluster.hcl (found via find_in_parent_folders),
# so this file must stay cluster-agnostic.

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
  # Condition consumed by the child stub's exclude block. Terragrunt does
  # not merge exclude blocks from included files, so the stub declares the
  # block and reads this condition via include.unit.locals.exclude_unit.
  exclude_unit = !local.cluster_enabled || local.skip_destroy || local.skip_apply

}

# Skip secrets module unless explicitly requested
# - On destroy: skip unless TALOS_DESTROY_SECRETS=1
# - On apply/plan: skip unless TALOS_REGENERATE_SECRETS=1

terraform {
  source = "${get_repo_root()}/terraform/infra/modules/talos_secrets"

  before_hook "enforce_cluster_enabled" {
    commands = ["init", "validate", "plan", "apply", "destroy", "refresh", "import", "output", "state", "console"]
    execute = ["bash", "-c", "if [ \"${local.cluster_enabled}\" != \"true\" ]; then echo 'ERROR: cluster-${local.tenant_id} is disabled (enabled=false in cluster.hcl). This module is excluded from run-all by design; refusing a direct single-unit command here too. Set enabled=true first if this is intentional.' >&2; exit 1; fi"]
  }

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
