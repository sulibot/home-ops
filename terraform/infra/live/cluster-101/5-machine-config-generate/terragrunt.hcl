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
      pods_ipv4          = format("10.%d.240.0/20", local.cluster_config.cluster_id)
      pods_ipv6          = "fd00:${local.cluster_config.cluster_id}:240::/60"
      services_ipv4      = format("10.%d.96.0/24", local.cluster_config.cluster_id)
      services_ipv6      = "fd00:${local.cluster_config.cluster_id}:96::/112"
      loadbalancers_ipv4 = format("10.%d.27.0/24", local.cluster_config.cluster_id)
      loadbalancers_ipv6 = "fd00:${local.cluster_config.cluster_id}:1b::/120"
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

# COMMENTED OUT: Custom installer with FRR extension (replaced by factory-based BIRD2)
# To rollback to FRR custom installer, uncomment this block and update installer_image input
# dependency "custom_installer" {
#   config_path = "../1-talos-install-image-build"
#
#   mock_outputs = {
#     installer_image = "ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0-beta.0"
#   }
#   mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
# }

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
  cilium_values_path = "${get_repo_root()}/kubernetes/apps/networking/cilium/app/values.yaml"

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
  # Use standard Talos installer (extensions loaded separately from system_extensions)
  installer_image   = "ghcr.io/siderolabs/installer:${local.versions.talos_version}"

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
