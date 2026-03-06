include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  tenant_id      = local.cluster_config.tenant_id
  context        = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals

  cluster_enabled = try(local.cluster_config.enabled, true)

  versions                 = local.context.versions
  install_schematic_config = local.context.install_schematic
  ipv6_prefixes            = local.context.ipv6_prefixes
  network_infra            = local.context.network_infra
  app_versions             = local.context.app_versions
  schematic_catalog        = local.context.artifacts_schematic_catalog
}

skip = !local.cluster_enabled

# Depend on compute module to get VM IP addresses and network configuration
# This is an internal cluster dependency and safe for run-all.
dependency "nodes" {
  config_path = "../compute"

  mock_outputs = {
    node_ips = {
      format("%scp01", local.cluster_config.cluster_name) = { public_ipv6 = format("fd00:%d::11", local.tenant_id), public_ipv4 = format("10.%d.0.11", local.tenant_id), ip_suffix = 11 }
      format("%scp02", local.cluster_config.cluster_name) = { public_ipv6 = format("fd00:%d::12", local.tenant_id), public_ipv4 = format("10.%d.0.12", local.tenant_id), ip_suffix = 12 }
      format("%scp03", local.cluster_config.cluster_name) = { public_ipv6 = format("fd00:%d::13", local.tenant_id), public_ipv4 = format("10.%d.0.13", local.tenant_id), ip_suffix = 13 }
      format("%swk01", local.cluster_config.cluster_name) = { public_ipv6 = format("fd00:%d::21", local.tenant_id), public_ipv4 = format("10.%d.0.21", local.tenant_id), ip_suffix = 21 }
      format("%swk02", local.cluster_config.cluster_name) = { public_ipv6 = format("fd00:%d::22", local.tenant_id), public_ipv4 = format("10.%d.0.22", local.tenant_id), ip_suffix = 22 }
      format("%swk03", local.cluster_config.cluster_name) = { public_ipv6 = format("fd00:%d::23", local.tenant_id), public_ipv4 = format("10.%d.0.23", local.tenant_id), ip_suffix = 23 }
    }
    k8s_network_config = {
      pods_ipv4          = format("10.%d.224.0/20", local.tenant_id)
      pods_ipv6          = "fd00:${local.tenant_id}:224::/60"
      services_ipv4      = format("10.%d.96.0/24", local.tenant_id)
      services_ipv6      = "fd00:${local.tenant_id}:96::/108"
      loadbalancers_ipv4 = format("10.%d.250.0/24", local.tenant_id)
      loadbalancers_ipv6 = "fd00:${local.tenant_id}:250::/112"
      talosVersion       = local.versions.talos_version
      kubernetesVersion  = startswith(local.versions.kubernetes_version, "v") ? local.versions.kubernetes_version : "v${local.versions.kubernetes_version}"
    }
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

terraform {
  source = "../../../../modules/talos_config"

  before_hook "validate_artifact_schematic_catalog" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -euo pipefail
        if [ ! -f "${local.context.artifacts_schematic_catalog_path}" ]; then
          echo "ERROR: Artifact schematic catalog not found: ${local.context.artifacts_schematic_catalog_path}"
          echo "Run: cd ${get_repo_root()}/terraform/infra/live/artifacts/schematic && terragrunt apply"
          exit 1
        fi
        echo "✓ Artifact schematic catalog found"
      EOT
    ]
  }

  # Validate upstream configurations before apply
  before_hook "validate_upstream_configs" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        REPO_ROOT="${get_repo_root()}"
        CLUSTER_ID="${local.tenant_id}"
        TALENV_FILE="$REPO_ROOT/talos/clusters/cluster-$CLUSTER_ID/talenv.yaml"

        if [ ! -f "$TALENV_FILE" ]; then
          echo "ERROR: $TALENV_FILE does not exist"
          echo "Please run: terragrunt apply --terragrunt-working-dir ../compute"
          exit 1
        fi

        TALENV_TALOS_VERSION=$(grep '^talosVersion:' "$TALENV_FILE" | awk '{print $2}' | tr -d '"')
        EXPECTED_TALOS_VERSION="${local.versions.talos_version}"

        if [ "$TALENV_TALOS_VERSION" != "$EXPECTED_TALOS_VERSION" ]; then
          echo "ERROR: talenv.yaml Talos version mismatch"
          echo "  Expected: $EXPECTED_TALOS_VERSION (from common/versions.hcl)"
          echo "  Found:    $TALENV_TALOS_VERSION (in talenv.yaml)"
          echo ""
          echo "This means compute module needs to be re-applied to regenerate talenv.yaml"
          echo "Run: terragrunt apply --terragrunt-working-dir ../compute"
          exit 1
        fi

        TALENV_K8S_VERSION=$(grep '^kubernetesVersion:' "$TALENV_FILE" | awk '{print $2}' | tr -d '"')
        EXPECTED_K8S_VERSION="${local.versions.kubernetes_version}"

        if [[ ! "$EXPECTED_K8S_VERSION" =~ ^v ]]; then
          EXPECTED_K8S_VERSION="v$EXPECTED_K8S_VERSION"
        fi

        if [ "$TALENV_K8S_VERSION" != "$EXPECTED_K8S_VERSION" ]; then
          echo "ERROR: talenv.yaml Kubernetes version mismatch"
          echo "  Expected: $EXPECTED_K8S_VERSION (from common/versions.hcl)"
          echo "  Found:    $TALENV_K8S_VERSION (in talenv.yaml)"
          echo ""
          echo "This means compute module needs to be re-applied to regenerate talenv.yaml"
          echo "Run: terragrunt apply --terragrunt-working-dir ../compute"
          exit 1
        fi

        echo "✓ talenv.yaml versions validated successfully"
      EOT
    ]
  }

  # Automatically export talosconfig after successful apply
  after_hook "export_talosconfig" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "cd ${get_repo_root()} && mkdir -p talos/clusters/cluster-${local.tenant_id} && cd ${get_terragrunt_dir()} && terragrunt output -raw talosconfig > ${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/talosconfig"]
    run_on_error = false
  }

  # Export machine configs for troubleshooting (not committed)
  after_hook "export_machine_configs" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -e
      cd ${get_repo_root()}
      mkdir -p talos/clusters/cluster-${local.tenant_id}
      cd ${get_terragrunt_dir()}

      terragrunt output -json machine_configs | \
        jq -r 'to_entries | map(select(.value.machine_type == "controlplane")) | first | .value.machine_configuration + "\n---\n" + .value.config_patch' > \
        ${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/controlplane.yaml

      terragrunt output -json machine_configs | \
        jq -r 'to_entries | map(select(.value.machine_type == "worker")) | first | .value.machine_configuration + "\n---\n" + .value.config_patch' > \
        ${get_repo_root()}/talos/clusters/cluster-${local.tenant_id}/worker.yaml

      echo "✓ Exported machine configs for troubleshooting (not committed to git)"
    EOT
    ]
    run_on_error = false
  }

  after_hook "export_cilium_bgp_node_configs" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
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

inputs = {
  cilium_bgp_config_path = "${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/bgp/bgp.yaml"
  cilium_lb_pool_path    = "${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/ippool/lb-pool.yaml"

  frr_template_path = "${get_repo_root()}/FRR/frr-talos-extension/frr.conf.j2"

  cluster_name = local.cluster_config.cluster_name
  cluster_id   = local.tenant_id

  talos_version      = local.versions.talos_version
  kubernetes_version = local.versions.kubernetes_version

  # Talos VIP is IPv6 in this config; use IPv6 VIP as cluster endpoint.
  cluster_endpoint = format(
    "https://[fd00:%d%s]:6443",
    local.tenant_id,
    local.network_infra.addressing.vip_ipv6_suffix,
  )
  vip_ipv6 = format(
    "fd00:%d%s",
    local.tenant_id,
    local.network_infra.addressing.vip_ipv6_suffix,
  )
  vip_ipv4 = format(
    "10.%d.0%s",
    local.tenant_id,
    local.network_infra.addressing.vip_ipv4_suffix,
  )

  all_node_ips = dependency.nodes.outputs.node_ips

  pod_cidr_ipv6      = dependency.nodes.outputs.k8s_network_config.pods_ipv6
  pod_cidr_ipv4      = dependency.nodes.outputs.k8s_network_config.pods_ipv4
  service_cidr_ipv6  = dependency.nodes.outputs.k8s_network_config.services_ipv6
  service_cidr_ipv4  = dependency.nodes.outputs.k8s_network_config.services_ipv4
  loadbalancers_ipv4 = dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv4
  loadbalancers_ipv6 = dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv6

  installer_image = "factory.talos.dev/installer/${local.schematic_catalog.schematic_id}:${local.versions.talos_version}"

  dns_servers = [
    local.network_infra.dns_servers.ipv6,
    local.network_infra.dns_servers.ipv4,
  ]

  ntp_servers       = local.network_infra.ntp_servers
  registry_mirrors  = local.network_infra.registry_mirrors
  gua_prefix        = local.ipv6_prefixes.delegated_prefixes["vnet${local.tenant_id}"]
  gua_gateway       = local.ipv6_prefixes.delegated_gateways["vnet${local.tenant_id}"]
  kernel_args       = local.install_schematic_config.install_kernel_args
  system_extensions = concat(local.install_schematic_config.install_system_extensions, local.install_schematic_config.install_custom_extensions)

  enable_node_swap      = local.context.talos_defaults.enable_node_swap
  kubelet_swap_behavior = local.context.talos_defaults.kubelet_swap_behavior
  swap_swappiness       = local.context.talos_defaults.swap_swappiness
  swap_size             = local.context.talos_defaults.swap_size

  install_disk = local.context.talos_defaults.install_disk

  bgp_asn_base            = local.network_infra.bgp.asn_base
  bgp_remote_asn          = local.network_infra.bgp.remote_asn
  bgp_interface           = local.network_infra.bgp.interface
  bgp_enable_bfd          = local.network_infra.bgp.enable_bfd
  bgp_advertise_loopbacks = local.network_infra.bgp.advertise_loopbacks

  bgp_cilium_allowed_prefixes = {
    ipv4 = [
      dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv4,
      dependency.nodes.outputs.k8s_network_config.pods_ipv4,
    ]
    ipv6 = [
      dependency.nodes.outputs.k8s_network_config.loadbalancers_ipv6,
      dependency.nodes.outputs.k8s_network_config.pods_ipv6,
    ]
  }

  machine_secrets      = dependency.secrets.outputs.machine_secrets
  client_configuration = dependency.secrets.outputs.client_configuration
}
