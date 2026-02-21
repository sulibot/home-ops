include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Depend on the nodes module to get VM IP addresses and network configuration
dependency "nodes" {
  config_path = "../compute"

  mock_outputs = {
    node_ips = {
      "solcp01" = { public_ipv6 = "fd00:101::11", public_ipv4 = "10.0.101.11", ip_suffix = 11 }
      "solcp02" = { public_ipv6 = "fd00:101::12", public_ipv4 = "10.0.101.12", ip_suffix = 12 }
      "solcp03" = { public_ipv6 = "fd00:101::13", public_ipv4 = "10.0.101.13", ip_suffix = 13 }
      "solwk01" = { public_ipv6 = "fd00:101::21", public_ipv4 = "10.0.101.21", ip_suffix = 21 }
      "solwk02" = { public_ipv6 = "fd00:101::22", public_ipv4 = "10.0.101.22", ip_suffix = 22 }
      "solwk03" = { public_ipv6 = "fd00:101::23", public_ipv4 = "10.0.101.23", ip_suffix = 23 }
    }
    k8s_network_config = {
      pods_ipv4          = format("10.%d.224.0/20", local.cluster_config.cluster_id)
      pods_ipv6          = "fd00:${local.cluster_config.cluster_id}:224::/60"
      services_ipv4      = format("10.%d.96.0/24", local.cluster_config.cluster_id)
      services_ipv6      = "fd00:${local.cluster_config.cluster_id}:96::/108"
      loadbalancers_ipv4 = format("10.%d.250.0/24", local.cluster_config.cluster_id)
      loadbalancers_ipv6 = "fd00:${local.cluster_config.cluster_id}:250::/112"
      talosVersion       = "v1.11.5"
      kubernetesVersion  = "v1.31.4"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "image" {
  config_path = "../../../artifacts/registry"

  mock_outputs = {
    talos_image_id = "mock-schematic-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "secrets" {
  config_path = "../secrets"

  mock_outputs = {
    machine_secrets = {
      cluster = "mock"
    }
    client_configuration = {
      ca_certificate     = "mock-ca"
      client_certificate = "mock-cert"
      client_key         = "mock-key"
    }
    secrets_yaml = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "destroy"]
}

# Talos Image Factory schematic (replaces custom image building)
dependency "schematic" {
  config_path = "../../../artifacts/schematic"

  mock_outputs = {
    schematic_id = "mock-schematic-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../../modules/talos_config"

  # Validate upstream configurations before apply
  before_hook "validate_upstream_configs" {
    commands = ["apply", "plan"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        REPO_ROOT="${get_repo_root()}"
        CLUSTER_ID="${local.cluster_config.cluster_id}"
        TALENV_FILE="$REPO_ROOT/talos/clusters/cluster-$CLUSTER_ID/talenv.yaml"

        # Check if talenv.yaml exists
        if [ ! -f "$TALENV_FILE" ]; then
          echo "ERROR: $TALENV_FILE does not exist"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../4-talos-vms-create"
          exit 1
        fi

        # Validate Talos version matches (camelCase field name)
        TALENV_TALOS_VERSION=$(grep '^talosVersion:' "$TALENV_FILE" | awk '{print $2}' | tr -d '"')
        EXPECTED_TALOS_VERSION="${local.versions.talos_version}"

        if [ "$TALENV_TALOS_VERSION" != "$EXPECTED_TALOS_VERSION" ]; then
          echo "ERROR: talenv.yaml Talos version mismatch"
          echo "  Expected: $EXPECTED_TALOS_VERSION (from common/versions.hcl)"
          echo "  Found:    $TALENV_TALOS_VERSION (in talenv.yaml)"
          echo ""
          echo "This means module 4-talos-vms-create needs to be re-applied to regenerate talenv.yaml"
          echo "Run: terragrunt apply --terragrunt-working-dir ../4-talos-vms-create"
          exit 1
        fi

        # Validate Kubernetes version matches (camelCase field name)
        TALENV_K8S_VERSION=$(grep '^kubernetesVersion:' "$TALENV_FILE" | awk '{print $2}' | tr -d '"')
        EXPECTED_K8S_VERSION="${local.versions.kubernetes_version}"

        # Add 'v' prefix to expected version if not present (versions.hcl may omit it)
        if [[ ! "$EXPECTED_K8S_VERSION" =~ ^v ]]; then
          EXPECTED_K8S_VERSION="v$EXPECTED_K8S_VERSION"
        fi

        if [ "$TALENV_K8S_VERSION" != "$EXPECTED_K8S_VERSION" ]; then
          echo "ERROR: talenv.yaml Kubernetes version mismatch"
          echo "  Expected: $EXPECTED_K8S_VERSION (from common/versions.hcl)"
          echo "  Found:    $TALENV_K8S_VERSION (in talenv.yaml)"
          echo ""
          echo "This means module 4-talos-vms-create needs to be re-applied to regenerate talenv.yaml"
          echo "Run: terragrunt apply --terragrunt-working-dir ../4-talos-vms-create"
          exit 1
        fi

        echo "✓ talenv.yaml versions validated successfully"
      EOT
    ]
  }

  # Check if upstream dependencies have been applied
  before_hook "check_dependencies_applied" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        echo "Checking if upstream dependencies have been applied..."

        # Navigate to module 4 directory from repo root
        MODULE_1_DIR="${get_repo_root()}/terraform/infra/live/clusters/cluster-${local.cluster_config.cluster_id}/compute"

        if [ ! -d "$MODULE_1_DIR" ]; then
          echo "ERROR: Module 4 directory not found at $MODULE_1_DIR"
          exit 1
        fi

        cd "$MODULE_1_DIR"

        # Check if module 4 has state (VMs created)
        if ! terragrunt state list &>/dev/null; then
          echo "ERROR: Module 4-talos-vms-create has no Terraform state"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../4-talos-vms-create"
          exit 1
        fi

        # Check if module 4 has node_ips output
        if ! terragrunt output -json node_ips &>/dev/null; then
          echo "ERROR: Module 4-talos-vms-create has no node_ips output"
          echo "This indicates VMs may not be fully created"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../4-talos-vms-create"
          exit 1
        fi

        echo "✓ Dependencies validated successfully"
      EOT
    ]
  }

  # Automatically export talosconfig after successful apply
  after_hook "export_talosconfig" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "cd ${get_repo_root()} && mkdir -p talos/clusters/cluster-${local.cluster_config.cluster_id} && cd ${get_terragrunt_dir()} && terragrunt output -raw talosconfig > ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/talosconfig"]
    run_on_error = false
  }

  # Export machine configs for troubleshooting (not committed)
  after_hook "export_machine_configs" {
    commands     = ["apply"]
    execute      = ["bash", "-c", <<-EOT
      set -e
      cd ${get_repo_root()}
      mkdir -p talos/clusters/cluster-${local.cluster_config.cluster_id}
      cd ${get_terragrunt_dir()}

      # Export controlplane config (machine_configuration + config_patch merged)
      terragrunt output -json machine_configs | \
        jq -r '.solcp01 | .machine_configuration + "\n---\n" + .config_patch' > \
        ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/controlplane.yaml

      # Export worker config (machine_configuration + config_patch merged)
      terragrunt output -json machine_configs | \
        jq -r '.solwk01 | .machine_configuration + "\n---\n" + .config_patch' > \
        ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/worker.yaml

      echo "✓ Exported machine configs for troubleshooting (not committed to git)"
    EOT
    ]
    run_on_error = false
  }

  after_hook "export_cilium_bgp_node_configs" {
    commands     = ["apply"]
    execute      = ["bash", "-c", <<-EOT
      set -e
      cd ${get_terragrunt_dir()}
      terragrunt output -raw cilium_bgp_node_configs_yaml > \
        ${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/bgp/node-configs.yaml
      echo "✓ Exported Cilium BGP node configs"
    EOT
    ]
    run_on_error = false
  }

}

locals {
  # Read cluster configuration
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals

  # Read common configurations
  versions                 = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  install_schematic_config = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
  ipv6_prefixes            = read_terragrunt_config(find_in_parent_folders("common/ipv6-prefixes.hcl")).locals

  # Read centralized infrastructure configurations
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  app_versions  = read_terragrunt_config(find_in_parent_folders("common/application-versions.hcl")).locals
}


inputs = {
  # Cilium config file paths (single source of truth from Flux directory)
  cilium_values_path     = "${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/app/values.yaml"
  cilium_bgp_config_path = "${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/bgp/bgp.yaml"
  cilium_lb_pool_path    = "${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/ippool/lb-pool.yaml"

  # FRR extension template (mounted into container to override baked-in version)
  frr_template_path = "${get_repo_root()}/FRR/frr-talos-extension/frr.conf.j2"

  # Cluster identity
  cluster_name = local.cluster_config.cluster_name
  cluster_id   = local.cluster_config.cluster_id

  # Versions
  talos_version      = local.versions.talos_version
  kubernetes_version = local.versions.kubernetes_version

  # Control plane VIP endpoint (dual-stack) - using centralized VIP suffix patterns
  cluster_endpoint = format("https://[fd00:%d%s]:6443",
    local.cluster_config.cluster_id,
    local.network_infra.addressing.vip_ipv6_suffix
  )
  vip_ipv6 = format("fd00:%d%s",
    local.cluster_config.cluster_id,
    local.network_infra.addressing.vip_ipv6_suffix
  )
  vip_ipv4 = format("10.0.%d%s",
    local.cluster_config.cluster_id,
    local.network_infra.addressing.vip_ipv4_suffix
  )

  # All node IPs - module will separate control plane from workers
  all_node_ips = dependency.nodes.outputs.node_ips

  # Network configuration from nodes module
  pod_cidr_ipv6     = dependency.nodes.outputs.k8s_network_config.pods_ipv6
  pod_cidr_ipv4     = dependency.nodes.outputs.k8s_network_config.pods_ipv4
  service_cidr_ipv6 = dependency.nodes.outputs.k8s_network_config.services_ipv6
  service_cidr_ipv4 = dependency.nodes.outputs.k8s_network_config.services_ipv4
  loadbalancers_ipv4 = dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv4
  loadbalancers_ipv6 = dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv6
  # Use Talos Image Factory installer (all extensions are now official)
  # Format: factory.talos.dev/installer/<schematic-id>:<version>
  installer_image = "factory.talos.dev/installer/${dependency.schematic.outputs.schematic_id}:${local.versions.talos_version}"

  # DNS servers from centralized infrastructure config
  dns_servers = [
    local.network_infra.dns_servers.ipv6,
    local.network_infra.dns_servers.ipv4,
  ]

  # NTP servers from centralized infrastructure config
  ntp_servers = local.network_infra.ntp_servers

  # OCI pull-through registry cache (single source of truth in network-infrastructure.hcl)
  registry_mirrors = local.network_infra.registry_mirrors

  # IPv6 GUA (Global Unicast Address) for internet reachability
  # Uses delegated prefix per vnet to avoid ULA-only egress.
  gua_prefix  = local.ipv6_prefixes.delegated_prefixes["vnet${local.cluster_config.cluster_id}"]
  gua_gateway = local.ipv6_prefixes.delegated_gateways["vnet${local.cluster_config.cluster_id}"]

  # Schematic configuration for Talos image customization (from install schematic)
  # GPU passthrough is disabled - using default kernel args only
  kernel_args = local.install_schematic_config.install_kernel_args
  system_extensions = concat(
    local.install_schematic_config.install_system_extensions,
    local.install_schematic_config.install_custom_extensions
  )

  # Install disk
  install_disk = "/dev/sda"

  # BGP Configuration - from centralized network infrastructure
  bgp_asn_base            = local.network_infra.bgp.asn_base
  bgp_remote_asn          = local.network_infra.bgp.remote_asn
  bgp_interface           = local.network_infra.bgp.interface
  bgp_enable_bfd          = local.network_infra.bgp.enable_bfd
  bgp_advertise_loopbacks = local.network_infra.bgp.advertise_loopbacks
  bgp_cilium_allowed_prefixes = {
    ipv4 = [
      dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv4,
      dependency.nodes.outputs.k8s_network_config.pods_ipv4
    ]
    ipv6 = [
      dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv6,
      dependency.nodes.outputs.k8s_network_config.pods_ipv6
    ]
  }

  # Application versions - from centralized config
  cilium_version = local.app_versions.applications.cilium_version

  # GPU driver configuration is now per-node (passed through all_node_ips from cluster_core)
  # The enable_i915 global flag is deprecated in favor of per-node gpu_passthrough config

  # Talos secrets and client configuration from dedicated secrets stack
  machine_secrets      = dependency.secrets.outputs.machine_secrets
  client_configuration = dependency.secrets.outputs.client_configuration
}
