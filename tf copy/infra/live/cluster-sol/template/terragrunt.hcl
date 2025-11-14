include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../../../modules/talos_template"
}

dependency "image" {
  config_path = "../image"
}

locals {
  cluster = read_terragrunt_config(find_in_parent_folders("cluster.hcl")).locals
  nodes   = read_terragrunt_config(find_in_parent_folders("nodes.hcl"))
}

inputs = {
  proxmox_node     = try(local.nodes.inputs.proxmox.node_primary, local.cluster.proxmox_nodes[0], "pve01")
  template_vmid    = local.cluster.cluster_id * 1000  # e.g., 101000 for cluster 101
  template_name    = "talos-${local.cluster.cluster_name}-template"
  talos_image_path = "${get_terragrunt_dir()}/../image/.terragrunt-cache/l0Bc_KwEFvkDClP7x0TFmXsvAiE/e2C0ToVNbrMVFQNJGCK-0OOktHM/.talos-images/${dependency.image.outputs.talos_image_file_name}"
  disk_storage     = try(local.nodes.inputs.proxmox.vm_datastore, "rbd-vm")
  disk_size        = "60G"
}
