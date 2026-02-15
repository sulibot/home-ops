# Config updates for running Talos nodes (Terragrunt-native approach)
# Uses Terragrunt hooks to apply full machine configs via talosctl
# Applies complete machine_configuration (base + patch merged)
# Safe for production - uses --mode=no-reboot to avoid disruption

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config   = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  talosconfig_path = "${get_repo_root()}/talos/clusters/cluster-101/talosconfig"
}

# Dependency on config stage (generates machine configs)
dependency "talos_config" {
  config_path = "../config"

  mock_outputs = {
    machine_configs = {}
    all_node_ips    = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Use a minimal Terraform config (just for state tracking)
terraform {
  source = "../../../../modules/talos_patch_config"

  # Generate machine config and patch files before terraform operations
  before_hook "generate_machine_configs" {
    commands = ["apply", "plan"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e
        echo "📝 Generating machine config and patch files..."

        REPO_ROOT="${get_repo_root()}"
        PATCH_DIR="$REPO_ROOT/terraform/infra/live/clusters/cluster-101/patch"
        CONFIG_DIR="$REPO_ROOT/terraform/infra/live/clusters/cluster-101/config"

        mkdir -p "$PATCH_DIR/configs"
        mkdir -p "$PATCH_DIR/patches"

        # Get config output
        CONFIG_JSON=$(cd "$CONFIG_DIR" && terragrunt output -json machine_configs 2>/dev/null || echo '{}')

        if [ "$CONFIG_JSON" != "{}" ]; then
          # Generate base machine configs
          echo "$CONFIG_JSON" | jq -r 'to_entries[] | [.key, .value.machine_configuration] | @tsv' | \
          while IFS=$'\t' read -r NODE MACHINE_CONFIG; do
            printf '%b' "$MACHINE_CONFIG" | yq eval -P '.' - > "$PATCH_DIR/configs/$NODE.yaml"
            echo "  ✓ Generated configs/$NODE.yaml (base)"
          done

          # Generate combined machine config patches (machine config + extension config)
          echo "$CONFIG_JSON" | jq -r 'to_entries[] | [.key, .value.machine_config_patch, .value.extension_config] | @tsv' | \
          while IFS=$'\t' read -r NODE PATCH EXT; do
            # Write machine config patch
            printf '%b' "$PATCH" | yq eval -P '.' - > "$PATCH_DIR/patches/$NODE.patch.yaml"
            # Append document separator and extension config
            echo "---" >> "$PATCH_DIR/patches/$NODE.patch.yaml"
            printf '%b' "$EXT" >> "$PATCH_DIR/patches/$NODE.patch.yaml"
            echo "  ✓ Generated patches/$NODE.patch.yaml (machine config + extension)"
          done
        fi
      EOT
    ]
  }

  # Apply machine configs with patches after terraform apply (Terragrunt-native approach)
  after_hook "apply_talos_configs" {
    commands     = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        REPO_ROOT="${get_repo_root()}"
        PATCH_DIR="$REPO_ROOT/terraform/infra/live/clusters/cluster-101/patch"
        CONFIG_DIR="$REPO_ROOT/terraform/infra/live/clusters/cluster-101/config"
        TALOSCONFIG="$REPO_ROOT/talos/clusters/cluster-101/talosconfig"

        export TALOSCONFIG

        echo ""
        echo "=========================================="
        echo "🔧 Applying Talos Machine Configurations"
        echo "=========================================="

        # Get node IPs
        NODE_IPS_JSON=$(cd "$CONFIG_DIR" && terragrunt output -json all_node_ips 2>/dev/null || echo '{}')

        if [ "$NODE_IPS_JSON" != "{}" ]; then
          echo "$NODE_IPS_JSON" | jq -r 'to_entries[] | [.key, .value.ipv6] | @tsv' | \
          while IFS=$'\t' read -r NODE NODE_IP; do
            if [ -f "$PATCH_DIR/configs/$NODE.yaml" ] && [ -f "$PATCH_DIR/patches/$NODE.patch.yaml" ]; then
              echo ""
              echo "Applying config to node: $NODE ($NODE_IP)"

              # Apply combined machine config + extension config patch
              if talosctl apply-config --nodes "$NODE_IP" --file "$PATCH_DIR/configs/$NODE.yaml" --config-patch @"$PATCH_DIR/patches/$NODE.patch.yaml" --mode no-reboot 2>&1; then
                echo "    ✅ Machine config + extension config applied"
              else
                echo "    ⚠️ Failed to apply config (continuing...)"
              fi
            fi
          done

          echo ""
          echo "=========================================="
          echo "✅ Config application complete"
          echo "=========================================="
        fi
      EOT
    ]
    run_on_error = false
  }
}

inputs = {
  talosconfig_path = "${get_repo_root()}/terraform/infra/live/clusters/cluster-101/talosconfig"
  machine_configs  = dependency.talos_config.outputs.machine_configs
  all_node_ips     = dependency.talos_config.outputs.all_node_ips
}
