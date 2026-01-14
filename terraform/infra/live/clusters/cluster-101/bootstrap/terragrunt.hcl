include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependencies {
  paths = ["../apply"]
}

dependency "talos_config" {
  config_path = "../config"

  mock_outputs = {
    talosconfig          = "mock"
    client_configuration = {
      ca_certificate     = "mock-ca"
      client_certificate = "mock-cert"
      client_key         = "mock-key"
    }
    cluster_endpoint    = "https://[fd00:101::10]:6443"
    machine_configs      = {}
    control_plane_ips    = {}
    all_node_names       = []
    all_node_ips         = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# NOTE: Bootstrap module applies configs itself (talos_machine_configuration_apply.nodes)
# Do NOT add dependency on apply module - that creates a circular dependency

terraform {
  source = "../../../../modules/talos_bootstrap"

  # Validate machine configs and secrets exist before bootstrap
  before_hook "validate_machine_configs" {
    commands = ["apply", "plan"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        REPO_ROOT="${get_repo_root()}"
        CLUSTER_ID="${local.cluster_config.cluster_id}"
        CLUSTER_DIR="$REPO_ROOT/talos/clusters/cluster-$CLUSTER_ID"

        # Check if talosconfig exists
        if [ ! -f "$CLUSTER_DIR/talosconfig" ]; then
          echo "ERROR: talosconfig does not exist at $CLUSTER_DIR/talosconfig"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../config"
          exit 1
        fi

        # Check if secrets exist
        if [ ! -f "$CLUSTER_DIR/secrets.sops.yaml" ]; then
          echo "ERROR: secrets.sops.yaml does not exist at $CLUSTER_DIR/secrets.sops.yaml"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../secrets"
          exit 1
        fi

        # Validate secrets are encrypted (should contain 'ENC[' pattern or 'sops:' marker)
        if ! grep -q 'ENC\[' "$CLUSTER_DIR/secrets.sops.yaml" && ! grep -q 'sops:' "$CLUSTER_DIR/secrets.sops.yaml"; then
          echo "ERROR: secrets.sops.yaml is not encrypted"
          echo "The file exists but doesn't appear to be SOPS-encrypted"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../secrets"
          exit 1
        fi

        # Check that talosconfig is newer than secrets (secrets get regenerated each apply)
        # Use stat command (macOS: -f %m, Linux: -c %Y)
        TALOSCONFIG_MTIME=$(stat -f %m "$CLUSTER_DIR/talosconfig" 2>/dev/null || stat -c %Y "$CLUSTER_DIR/talosconfig" 2>/dev/null || echo 0)
        SECRETS_MTIME=$(stat -f %m "$CLUSTER_DIR/secrets.sops.yaml" 2>/dev/null || stat -c %Y "$CLUSTER_DIR/secrets.sops.yaml" 2>/dev/null || echo 0)

        # Allow 10 second tolerance for file timestamp differences
        if [ $SECRETS_MTIME -gt 0 ] && [ $TALOSCONFIG_MTIME -gt 0 ] && [ $((SECRETS_MTIME - TALOSCONFIG_MTIME)) -gt 10 ]; then
          echo "WARNING: secrets.sops.yaml is newer than talosconfig"
          echo "This may indicate secrets were rotated without regenerating configs"
          echo "Consider re-running: terragrunt apply --terragrunt-working-dir ../config"
        fi

        echo "✓ Machine configs and secrets validated successfully"
      EOT
    ]
  }

  # Note: Removed wait_for_nodes hook - the Talos provider handles retries and timeouts
  # when applying configurations. The compute dependency ensures VMs exist before this runs.
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  app_versions   = read_terragrunt_config(find_in_parent_folders("common/application-versions.hcl")).locals
  secrets        = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/infra/live/common/secrets.sops.yaml"))
}

inputs = {
  cluster_id           = local.cluster_config.cluster_id
  talosconfig          = dependency.talos_config.outputs.talosconfig
  client_configuration = dependency.talos_config.outputs.client_configuration
  control_plane_nodes  = dependency.talos_config.outputs.control_plane_ips
  cluster_endpoint     = dependency.talos_config.outputs.cluster_endpoint

  # Flux GitOps configuration - from centralized config
  flux_git_repository = local.app_versions.gitops.flux_git_repository
  flux_git_branch     = local.app_versions.gitops.flux_git_branch
  flux_github_token   = local.secrets.github_token

  # SOPS AGE key for decrypting secrets (read from file to keep it out of state)
  sops_age_key         = get_env("SOPS_AGE_KEY_FILE", "") != "" ? file(get_env("SOPS_AGE_KEY_FILE")) : ""
}
