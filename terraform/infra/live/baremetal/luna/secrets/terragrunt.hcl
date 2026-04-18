locals {
  cluster_config   = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  context          = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals
  output_directory = "${get_repo_root()}/talos/clusters/${local.cluster_config.cluster_name}"

  cluster_enabled = try(local.cluster_config.enabled, true)

  terragrunt_command_env = lower(trimspace(get_env("TERRAGRUNT_COMMAND", "")))
  terragrunt_command     = local.terragrunt_command_env != "" ? local.terragrunt_command_env : lower(trimspace(get_env("TG_COMMAND", "")))

  destroy_secrets    = get_env("TALOS_DESTROY_SECRETS", "") != ""
  skip_destroy       = can(regex("destroy", local.terragrunt_command)) && !local.destroy_secrets
  regenerate_secrets = get_env("TALOS_REGENERATE_SECRETS", "") != ""
  skip_apply         = can(regex("apply|plan", local.terragrunt_command)) && !local.regenerate_secrets
}

skip = !local.cluster_enabled || local.skip_destroy || local.skip_apply

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/talos_secrets"

  after_hook "export_secrets" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -e
      mkdir -p "${local.output_directory}"
      cd ${get_terragrunt_dir()}

      terragrunt output -raw secrets_yaml > "${local.output_directory}/secrets.sops.yaml"
      sops -e -i "${local.output_directory}/secrets.sops.yaml"

      echo "✓ Exported and encrypted luna Talos secrets"
    EOT
    ]
    run_on_error = false
  }
}

inputs = {
  talos_version = local.context.versions.talos_version
}
