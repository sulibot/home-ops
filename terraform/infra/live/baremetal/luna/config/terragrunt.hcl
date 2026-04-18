include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  cluster_config   = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  context          = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals
  output_directory = "${get_repo_root()}/talos/clusters/${local.cluster_config.cluster_name}"

  cluster_enabled          = try(local.cluster_config.enabled, true)
  versions                 = local.context.versions
  install_schematic_config = local.context.install_schematic
  ipv6_prefixes            = local.context.ipv6_prefixes
  network_infra            = local.context.network_infra
  schematic_catalog        = local.context.artifacts_schematic_catalog

  node_ips = {
    (local.cluster_config.node.name) = {
      public_ipv4  = local.cluster_config.node.public_ipv4
      public_ipv6  = local.cluster_config.node.public_ipv6
      ip_suffix    = local.cluster_config.node.ip_suffix
      hostname     = local.cluster_config.node.hostname
      machine_type = local.cluster_config.node.machine_type
    }
  }

  pod_cidr_ipv4         = format(local.network_infra.addressing.pods_ipv4_pattern, local.cluster_config.cluster_id)
  pod_cidr_ipv6         = format(local.network_infra.addressing.pods_ipv6_pattern, local.cluster_config.cluster_id)
  service_cidr_ipv4     = format(local.network_infra.addressing.services_ipv4_pattern, local.cluster_config.cluster_id)
  service_cidr_ipv6     = format(local.network_infra.addressing.services_ipv6_pattern, local.cluster_config.cluster_id)
  loadbalancers_ipv4    = format(local.network_infra.addressing.loadbalancers_ipv4_pattern, local.cluster_config.cluster_id)
  loadbalancers_ipv6    = format(local.network_infra.addressing.loadbalancers_ipv6_pattern, local.cluster_config.cluster_id)
  delegated_prefix_key  = "vnet${local.cluster_config.cluster_id}"
  delegated_gua_prefix  = try(local.ipv6_prefixes.delegated_prefixes[local.delegated_prefix_key], "")
  delegated_gua_gateway = try(local.ipv6_prefixes.delegated_gateways[local.delegated_prefix_key], "")
}

skip = !local.cluster_enabled

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
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
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

  after_hook "export_talosconfig" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -e
      mkdir -p "${local.output_directory}"
      cd ${get_terragrunt_dir()}
      terragrunt output -raw talosconfig > "${local.output_directory}/talosconfig"
      echo "✓ Exported luna talosconfig"
    EOT
    ]
    run_on_error = false
  }

  after_hook "export_machine_configs" {
    commands = ["apply"]
    execute = ["bash", "-c", <<-EOT
      set -e
      mkdir -p "${local.output_directory}"
      cd ${get_terragrunt_dir()}

      terragrunt output -json machine_configs | \
        jq -r 'to_entries | map(select(.value.machine_type == "controlplane")) | first | .value.machine_configuration + "\n---\n" + .value.config_patch' > \
        "${local.output_directory}/controlplane.yaml"

      terragrunt output -json machine_configs | \
        jq -r 'to_entries | map(select(.key == "${local.cluster_config.node.name}")) | first | .value.machine_configuration + "\n---\n" + .value.config_patch' > \
        "${local.output_directory}/${local.cluster_config.node.name}.yaml"

      echo "✓ Exported luna machine configs"
    EOT
    ]
    run_on_error = false
  }
}

inputs = {
  cilium_bgp_config_path = "${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/bgp/bgp.yaml"
  cilium_lb_pool_path    = "${get_repo_root()}/kubernetes/apps/tier-0-foundation/cilium/ippool/lb-pool.yaml"
  frr_template_path      = "${get_repo_root()}/FRR/frr-talos-extension/frr.conf.j2"

  cluster_name = local.cluster_config.cluster_name
  cluster_id   = local.cluster_config.cluster_id

  talos_version      = local.versions.talos_version
  kubernetes_version = local.versions.kubernetes_version

  cluster_endpoint = local.cluster_config.network.cluster_endpoint
  use_vip          = local.cluster_config.network.use_vip

  all_node_ips = local.node_ips

  pod_cidr_ipv6      = local.pod_cidr_ipv6
  pod_cidr_ipv4      = local.pod_cidr_ipv4
  service_cidr_ipv6  = local.service_cidr_ipv6
  service_cidr_ipv4  = local.service_cidr_ipv4
  loadbalancers_ipv4 = local.loadbalancers_ipv4
  loadbalancers_ipv6 = local.loadbalancers_ipv6

  installer_image = "factory.talos.dev/installer/${local.schematic_catalog.schematic_id}:${local.versions.talos_version}"

  dns_servers = [
    local.network_infra.dns_servers.ipv6,
    local.network_infra.dns_servers.ipv4,
  ]

  ntp_servers       = local.network_infra.ntp_servers
  registry_mirrors  = local.network_infra.registry_mirrors
  gua_prefix        = local.delegated_gua_prefix
  gua_gateway       = local.delegated_gua_gateway
  kernel_args       = local.install_schematic_config.install_kernel_args
  system_extensions = concat(local.install_schematic_config.install_system_extensions, local.install_schematic_config.install_custom_extensions)

  enable_node_swap      = local.context.talos_defaults.enable_node_swap
  kubelet_swap_behavior = local.context.talos_defaults.kubelet_swap_behavior
  swap_swappiness       = local.context.talos_defaults.swap_swappiness
  swap_size             = local.context.talos_defaults.swap_size
  ephemeral_max_size    = local.context.talos_defaults.ephemeral_max_size

  install_disk = local.context.talos_defaults.install_disk
  install_wipe = trimspace(lower(get_env("TALOS_INSTALL_WIPE", tostring(local.context.talos_defaults.install_wipe)))) == "true"

  bgp_asn_base                       = local.network_infra.bgp.asn_base
  bgp_remote_asn                     = local.network_infra.bgp.remote_asn
  bgp_interface                      = local.network_infra.bgp.interface
  bgp_enable_bfd                     = local.network_infra.bgp.enable_bfd
  bgp_advertise_loopbacks            = local.network_infra.bgp.advertise_loopbacks
  allow_scheduling_on_control_planes = true

  bgp_cilium_allowed_prefixes = {
    ipv4 = [
      local.loadbalancers_ipv4,
      local.pod_cidr_ipv4,
    ]
    ipv6 = [
      local.loadbalancers_ipv6,
      local.pod_cidr_ipv6,
    ]
  }

  machine_secrets      = dependency.secrets.outputs.machine_secrets
  client_configuration = dependency.secrets.outputs.client_configuration
}
