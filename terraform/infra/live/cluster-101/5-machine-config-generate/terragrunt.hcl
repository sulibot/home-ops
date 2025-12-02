include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Depend on the nodes module to get VM IP addresses and network configuration
dependency "nodes" {
  config_path = "../4-talos-vms-create"

  mock_outputs = {
    node_ips = {
      "solcp01" = { public_ipv6 = "fd00:101::11", public_ipv4 = "10.0.101.11", mesh_ipv6 = "fc00:101::11", mesh_ipv4 = "10.10.101.11" }
      "solcp02" = { public_ipv6 = "fd00:101::12", public_ipv4 = "10.0.101.12", mesh_ipv6 = "fc00:101::12", mesh_ipv4 = "10.10.101.12" }
      "solcp03" = { public_ipv6 = "fd00:101::13", public_ipv4 = "10.0.101.13", mesh_ipv6 = "fc00:101::13", mesh_ipv4 = "10.10.101.13" }
      "solwk01" = { public_ipv6 = "fd00:101::21", public_ipv4 = "10.0.101.21", mesh_ipv6 = "fc00:101::21", mesh_ipv4 = "10.10.101.21" }
      "solwk02" = { public_ipv6 = "fd00:101::22", public_ipv4 = "10.0.101.22", mesh_ipv6 = "fc00:101::22", mesh_ipv4 = "10.10.101.22" }
      "solwk03" = { public_ipv6 = "fd00:101::23", public_ipv4 = "10.0.101.23", mesh_ipv6 = "fc00:101::23", mesh_ipv4 = "10.10.101.23" }
    }
    k8s_network_config = {
      pods_ipv4          = "10.101.0.0/16"
      pods_ipv6          = "fd00:101:1::/60"
      services_ipv4      = "10.101.96.0/20"
      services_ipv6      = "fd00:101:96::/108"
      loadbalancers_ipv4 = "10.101.27.0/24"
      loadbalancers_ipv6 = "fd00:101:1b::/120"
      talosVersion       = "v1.11.5"
      kubernetesVersion  = "v1.31.4"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "image" {
  config_path = "../3-boot-iso-upload"

  mock_outputs = {
    talos_image_id = "mock-schematic-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "install_schematic" {
  config_path = "../2-talos-schematic-generate"

  mock_outputs = {
    schematic_id = "mock-install-schematic-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../modules/talos_config"

  # Automatically export talosconfig after successful apply
  after_hook "export_talosconfig" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "cd ${get_repo_root()} && mkdir -p talos/clusters/cluster-${local.cluster_config.cluster_id} && cd ${get_terragrunt_dir()} && terragrunt output -raw talosconfig > ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/talosconfig"]
    run_on_error = false
  }

  # Export and encrypt cluster secrets for node addition
  after_hook "export_secrets" {
    commands     = ["apply"]
    execute      = ["bash", "-c", <<-EOT
      set -e
      cd ${get_repo_root()}
      mkdir -p talos/clusters/cluster-${local.cluster_config.cluster_id}
      cd ${get_terragrunt_dir()}

      # Export secrets as YAML
      terragrunt output -raw secrets_yaml > \
        ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/secrets.sops.yaml

      # Encrypt with SOPS in place
      sops -e -i ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/secrets.sops.yaml

      echo "✓ Exported and encrypted secrets.sops.yaml"
    EOT
    ]
    run_on_error = false
  }

  # Export per-node machine configs
  after_hook "export_machine_configs" {
    commands     = ["apply"]
    execute      = ["bash", "-c", <<-EOT
      set -e
      cd ${get_repo_root()}
      mkdir -p talos/clusters/cluster-${local.cluster_config.cluster_id}
      cd ${get_terragrunt_dir()}

      # Export all per-node configs
      for node in solcp01 solcp02 solcp03 solwk01 solwk02 solwk03; do
        terragrunt output -json machine_configs | \
          jq -r ".[\"\$node\"].machine_configuration" > \
          ${get_repo_root()}/talos/clusters/cluster-${local.cluster_config.cluster_id}/\$node.yaml
      done

      echo "✓ Exported per-node machine configs (solcp01-03, solwk01-03)"
    EOT
    ]
    run_on_error = false
  }
}

locals {
  # Read cluster configuration
  cluster_config = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals

  # Read common configurations
  versions = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  install_schematic_config = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
}


inputs = {
  # Cilium values file path
  cilium_values_path = "${get_repo_root()}/kubernetes/apps/1-network/cilium/app/values.yaml"

  # Cluster identity
  cluster_name = local.cluster_config.cluster_name
  cluster_id   = local.cluster_config.cluster_id

  # Versions
  talos_version      = local.versions.talos_version
  kubernetes_version = local.versions.kubernetes_version

  # Control plane VIP endpoint (dual-stack)
  cluster_endpoint = "https://[fd00:${local.cluster_config.cluster_id}::10]:6443"
  vip_ipv6         = "fd00:${local.cluster_config.cluster_id}::10"
  vip_ipv4         = "10.0.${local.cluster_config.cluster_id}.10"

  # All node IPs - module will separate control plane from workers
  all_node_ips = dependency.nodes.outputs.node_ips

  # Network configuration from nodes module
  pod_cidr_ipv6     = dependency.nodes.outputs.k8s_network_config.pods_ipv6
  pod_cidr_ipv4     = dependency.nodes.outputs.k8s_network_config.pods_ipv4
  service_cidr_ipv6 = dependency.nodes.outputs.k8s_network_config.services_ipv6
  service_cidr_ipv4 = dependency.nodes.outputs.k8s_network_config.services_ipv4
  installer_image   = "factory.talos.dev/installer/${dependency.install_schematic.outputs.schematic_id}:${local.versions.talos_version}"

  dns_servers = [
    "fd00:${local.cluster_config.cluster_id}::fffe",  # IPv6 DNS
    "10.0.${local.cluster_config.cluster_id}.254",    # IPv4 DNS
  ]

  # Schematic configuration for Talos image customization (from install schematic)
  kernel_args       = local.install_schematic_config.install_kernel_args
  system_extensions = local.install_schematic_config.install_system_extensions

  # Install disk
  install_disk = "/dev/sda"
}
