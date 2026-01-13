locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  versions       = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals

  terragrunt_command_env = lower(trimspace(get_env("TERRAGRUNT_COMMAND", "")))
  terragrunt_command     = local.terragrunt_command_env != "" ? local.terragrunt_command_env : lower(trimspace(get_env("TG_COMMAND", "")))
  destroy_secrets        = get_env("TALOS_DESTROY_SECRETS", "") != ""
  skip_destroy           = can(regex("destroy", local.terragrunt_command)) && !local.destroy_secrets
}

skip = local.skip_destroy

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../modules/talos_secrets"

  # Export and encrypt cluster secrets for reuse
  after_hook "export_secrets" {
    commands     = ["apply"]
    execute      = ["bash", "-c", <<-EOT
      set -e
      cd ${get_repo_root()}
      mkdir -p talos/clusters/cluster-${local.cluster_config.cluster_id}
      cd ${get_terragrunt_dir()}

      terragrunt output -raw secrets_yaml > \
        ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/secrets.sops.yaml

      sops -e -i ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/secrets.sops.yaml

      echo "✓ Exported and encrypted secrets.sops.yaml"
    EOT
    ]
    run_on_error = false
  }
}

inputs = {
  talos_version = local.versions.talos_version
}
