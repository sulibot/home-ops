# Shared unit template: config-metal (bare-metal clusters; VM clusters use config-vm)
# Included by each metal cluster's config/terragrunt.hcl. All cluster-specific
# values come from that cluster's cluster.hcl (found via find_in_parent_folders),
# so this file must stay cluster-agnostic. Node inventory comes from the
# cluster.hcl `nodes` map; the install image comes from the sibling schematic
# unit's generated catalog.

locals {
  cluster_config   = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  cluster_id       = local.cluster_config.cluster_id
  tenant_id        = local.cluster_config.tenant_id
  context          = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals
  output_directory = "${get_repo_root()}/talos/clusters/cluster-${local.cluster_id}"

  cluster_enabled          = try(local.cluster_config.enabled, true)
  versions                 = local.context.versions
  install_schematic_config = local.context.install_schematic
  ipv6_prefixes            = local.context.ipv6_prefixes
  network_infra            = local.context.network_infra
  schematic_catalog_path   = "${get_terragrunt_dir()}/../schematic/schematic.json"
  schematic_catalog        = fileexists(local.schematic_catalog_path) ? jsondecode(file(local.schematic_catalog_path)) : {}

  node_ips = {
    for name, node in local.cluster_config.nodes :
    name => {
      public_ipv4      = node.public_ipv4
      public_ipv6      = node.public_ipv6
      ip_suffix        = node.ip_suffix
      hostname         = node.hostname
      machine_type     = node.machine_type
      extra_interfaces = try(node.extra_interfaces, [])
    }
  }

  pod_cidr_ipv4         = format(local.network_infra.addressing.pods_ipv4_pattern, local.cluster_id)
  pod_cidr_ipv6         = format(local.network_infra.addressing.pods_ipv6_pattern, local.cluster_id)
  service_cidr_ipv4     = format(local.network_infra.addressing.services_ipv4_pattern, local.cluster_id)
  service_cidr_ipv6     = format(local.network_infra.addressing.services_ipv6_pattern, local.cluster_id)
  loadbalancers_ipv4    = format(local.network_infra.addressing.loadbalancers_ipv4_pattern, local.cluster_id)
  loadbalancers_ipv6    = format(local.network_infra.addressing.loadbalancers_ipv6_pattern, local.cluster_id)
  delegated_prefix_key  = "vnet${local.cluster_id}"
  delegated_gua_prefix  = try(local.ipv6_prefixes.delegated_prefixes[local.delegated_prefix_key], "")
  delegated_gua_gateway = try(local.ipv6_prefixes.delegated_gateways[local.delegated_prefix_key], "")

  # Condition consumed by the child stub's exclude block. Terragrunt does
  # not merge exclude blocks from included files, so the stub declares the
  # block and reads this condition via include.unit.locals.exclude_unit.
  exclude_unit = !local.cluster_enabled
}

dependency "secrets" {
  config_path = "${get_terragrunt_dir()}/../secrets"

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
  source = "${get_repo_root()}/terraform/infra/modules/talos_config"

  before_hook "enforce_cluster_enabled" {
    commands = ["init", "validate", "plan", "apply", "destroy", "refresh", "import", "output", "state", "console"]
    execute = ["bash", "-c", "if [ \"${local.cluster_enabled}\" != \"true\" ]; then echo 'ERROR: cluster-${local.tenant_id} is disabled (enabled=false in cluster.hcl). This module is excluded from run-all by design; refusing a direct single-unit command here too. Set enabled=true first if this is intentional.' >&2; exit 1; fi"]
  }

  before_hook "validate_artifact_schematic_catalog" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -euo pipefail
        if [ ! -f "${local.schematic_catalog_path}" ]; then
          echo "ERROR: cluster-${local.cluster_id} bare-metal schematic catalog not found: ${local.schematic_catalog_path}"
          echo "Run: cd ${get_terragrunt_dir()}/../schematic && terragrunt apply"
          exit 1
        fi
        echo "✓ cluster-${local.cluster_id} bare-metal schematic catalog found"
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
      echo "✓ Exported cluster-${local.cluster_id} talosconfig"
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

      for node in $(terragrunt output -json machine_configs | jq -r 'keys[]'); do
        terragrunt output -json machine_configs | \
          jq -r --arg node "$node" 'to_entries | map(select(.key == $node)) | first | .value.machine_configuration + "\n---\n" + .value.config_patch' > \
          "${local.output_directory}/$node.yaml"
      done

      echo "✓ Exported cluster-${local.cluster_id} machine configs"
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
  cluster_id   = local.cluster_id

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

  ntp_servers      = local.network_infra.ntp_servers
  registry_mirrors = local.network_infra.registry_mirrors
  gua_prefix       = local.delegated_gua_prefix
  gua_gateway      = local.delegated_gua_gateway
  kernel_args      = local.install_schematic_config.install_kernel_args
  system_extensions = [
    for extension in concat(local.install_schematic_config.install_system_extensions, local.install_schematic_config.install_custom_extensions) :
    extension if !strcontains(extension, "qemu-guest-agent")
  ]

  enable_node_swap      = false
  kubelet_swap_behavior = local.context.talos_defaults.kubelet_swap_behavior
  swap_swappiness       = local.context.talos_defaults.swap_swappiness
  swap_size             = local.context.talos_defaults.swap_size
  ephemeral_max_size    = local.context.talos_defaults.ephemeral_max_size

  install_disk = local.context.talos_defaults.install_disk
  install_wipe = trimspace(lower(get_env("TALOS_INSTALL_WIPE", tostring(local.context.talos_defaults.install_wipe)))) == "true"

  bgp_asn_base = local.network_infra.bgp.asn_base
  bgp_remote_asn = local.network_infra.bgp.remote_asn
  # Module takes a single BGP interface; metal nodes declare theirs per-node,
  # so use the first node's (single-node clusters) or the shared default.
  bgp_interface                      = try(values(local.cluster_config.nodes)[0].interface, local.network_infra.bgp.interface)
  bgp_enable_bfd                     = false
  bgp_advertise_loopbacks            = local.network_infra.bgp.advertise_loopbacks
  allow_scheduling_on_control_planes = true
  user_volumes                       = try(local.cluster_config.user_volumes, [])

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
