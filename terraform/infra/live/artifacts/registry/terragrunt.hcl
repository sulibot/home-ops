# Publish boot ISO to Proxmox infrastructure
# Uploads the locally built ISO to Proxmox Ceph storage

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "build" {
  config_path = "../images"

  mock_outputs = {
    iso_path        = "/tmp/mock-talos.iso"
    iso_name        = "mock-talos-nocloud-amd64.iso"
    talos_version   = "v1.11.5"
    kubernetes_version = "1.31.4"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

terraform {
  source = "../../../modules/talos_proxmox_upload"
}

locals {
  # Import centralized Proxmox infrastructure configuration
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
}

inputs = {
  # ISO from build step
  iso_path           = dependency.build.outputs.iso_path
  iso_name           = dependency.build.outputs.iso_name
  talos_version      = dependency.build.outputs.talos_version
  kubernetes_version = dependency.build.outputs.kubernetes_version

  # Use centralized Proxmox infrastructure configuration
  proxmox_datastore_id   = local.proxmox_infra.storage.datastore_id
  proxmox_node_names     = local.proxmox_infra.proxmox_nodes
  proxmox_node_hostnames = values(local.proxmox_infra.proxmox_hostnames)
}
