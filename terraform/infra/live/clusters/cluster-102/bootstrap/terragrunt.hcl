include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id
  context        = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals

  cluster_enabled    = try(local.cluster_config.enabled, true)
  bootstrap_mode     = trimspace(lower(get_env("TALOS_BOOTSTRAP_MODE", "false"))) == "true"
  cluster_kubeconfig = "${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/kubeconfig"
  kubeconfig_exists  = fileexists(local.cluster_kubeconfig)
  kubernetes_api_ready = local.kubeconfig_exists && trimspace(run_cmd(
    "bash",
    "-lc",
    "KUBECONFIG='${local.cluster_kubeconfig}' timeout 8 kubectl get --raw=/readyz >/dev/null 2>&1 && echo true || echo false"
  )) == "true"
}

# Safety/perf: Skip bootstrap on repeat run-all only when API is actually reachable.
# Set TALOS_BOOTSTRAP_MODE=true to force running bootstrap explicitly.
skip = !local.cluster_enabled || (
  !local.bootstrap_mode &&
  local.kubernetes_api_ready
)

dependencies {
  paths = ["../apply"]
}

dependency "talos_config" {
  config_path = "../config"

  mock_outputs = {
    talosconfig = "mock"
    client_configuration = {
      ca_certificate     = "mock-ca"
      client_certificate = "mock-cert"
      client_key         = "mock-key"
    }
    cluster_endpoint  = format("https://[fd00:%d::10]:6443", local.tenant_id)
    machine_configs   = {}
    control_plane_ips = {}
    all_node_names    = []
    all_node_ips      = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

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
        CLUSTER_ID="${local.tenant_id}"
        CLUSTER_DIR="$REPO_ROOT/talos/clusters/cluster-$CLUSTER_ID"

        if [ ! -f "$CLUSTER_DIR/talosconfig" ]; then
          echo "ERROR: talosconfig does not exist at $CLUSTER_DIR/talosconfig"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../config"
          exit 1
        fi

        if [ ! -f "$CLUSTER_DIR/secrets.sops.yaml" ]; then
          echo "ERROR: secrets.sops.yaml does not exist at $CLUSTER_DIR/secrets.sops.yaml"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../secrets"
          exit 1
        fi

        if ! grep -q 'ENC\[' "$CLUSTER_DIR/secrets.sops.yaml" && ! grep -q 'sops:' "$CLUSTER_DIR/secrets.sops.yaml"; then
          echo "ERROR: secrets.sops.yaml is not encrypted"
          echo "The file exists but doesn't appear to be SOPS-encrypted"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../secrets"
          exit 1
        fi

        TALOSCONFIG_MTIME=$(stat -f %m "$CLUSTER_DIR/talosconfig" 2>/dev/null || stat -c %Y "$CLUSTER_DIR/talosconfig" 2>/dev/null || echo 0)
        SECRETS_MTIME=$(stat -f %m "$CLUSTER_DIR/secrets.sops.yaml" 2>/dev/null || stat -c %Y "$CLUSTER_DIR/secrets.sops.yaml" 2>/dev/null || echo 0)

        if [ $SECRETS_MTIME -gt 0 ] && [ $TALOSCONFIG_MTIME -gt 0 ] && [ $((SECRETS_MTIME - TALOSCONFIG_MTIME)) -gt 10 ]; then
          echo "WARNING: secrets.sops.yaml is newer than talosconfig"
          echo "This may indicate secrets were rotated without regenerating configs"
          echo "Consider re-running: terragrunt apply --terragrunt-working-dir ../config"
        fi

        echo "✓ Machine configs and secrets validated successfully"
      EOT
    ]
  }

}

inputs = {
  cluster_id           = local.tenant_id
  talosconfig          = dependency.talos_config.outputs.talosconfig
  client_configuration = dependency.talos_config.outputs.client_configuration
  control_plane_nodes  = dependency.talos_config.outputs.control_plane_ips
  cluster_endpoint     = dependency.talos_config.outputs.cluster_endpoint

  repo_root = get_repo_root()
}
