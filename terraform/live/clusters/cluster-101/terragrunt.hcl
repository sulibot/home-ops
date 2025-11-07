include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/clusters/cluster"
}


locals {
  globals = read_terragrunt_config(find_in_parent_folders("common/globals.hcl")).locals
  secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/live/common/secrets.sops.yaml"))

  cluster_defaults = read_terragrunt_config(find_in_parent_folders("common/cluster_defaults.hcl")).locals.inputs
  cluster = read_terragrunt_config("cluster.hcl").locals.inputs
}


inputs = merge(
  local.globals,
  local.cluster_defaults,
  local.cluster,
  {
    git_repo_root       = get_repo_root()
    
    pve_api_token_id     = local.secrets.pve_api_token_id
    pve_api_token_secret = local.secrets.pve_api_token_secret
    pve_endpoint         = local.secrets.pve_endpoint
    pve_username         = local.secrets.pve_username
    pve_password         = local.secrets.pve_password
    routeros_username   = local.secrets.routeros_username
    routeros_password    = local.secrets.routeros_password
    routeros_hosturl     = local.secrets.routeros_hosturl

    cluster_name         = "sol"
    cluster_id           = 101

    control_plane = {
      role             = "control-plane"
      role_id          = "cp"
      cpu_count        = 2
      memory_mb        = 8192
      instance_count   = 3
      disk_size_gb     = 20
      segment_start    = 11
      k8s_vip_rise     = 3
      k8s_vip_fall     = 3
      k8s_vip_cooldown = 10
      enable_ipv4    = true
      enable_ipv6    = true
    }
    workers = {
      role             = "worker"
      role_id          = "wk"
      cpu_count        = 2
      memory_mb        = 16384
      instance_count   = 3
      disk_size_gb     = 100
      segment_start    = 21
      enable_ipv4       = true
      enable_ipv6       = true
    }
  }
)
  
