terraform {
  source = "../../../modules/proxmox_ha"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "versions" {
  path = find_in_parent_folders("common/versions.hcl")
}

include "credentials" {
  path = find_in_parent_folders("common/credentials.hcl")
}

locals {
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  context       = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals
  network_infra = local.context.network_infra
  proxmox_infra = local.context.proxmox_infra

  cluster_paths = {
    cluster-101 = "${get_repo_root()}/terraform/infra/live/clusters/cluster-101/cluster.hcl"
    cluster-102 = "${get_repo_root()}/terraform/infra/live/clusters/cluster-102/cluster.hcl"
  }

  clusters = {
    for name, path in local.cluster_paths :
    name => read_terragrunt_config(path).locals
  }

  enabled_ha_clusters = {
    for name, cluster in local.clusters : name => cluster
    if try(cluster.enabled, true) && try(cluster.proxmox_ha.enabled, false)
  }

  cluster_vm_ids = {
    for name, cluster in local.enabled_ha_clusters : name => concat(
      [
        for i in range(cluster.controlplanes) :
        tonumber(format("%d0%d", cluster.tenant_id, i + local.network_infra.addressing.controlplane_offset))
      ],
      [
        for i in range(cluster.workers) :
        tonumber(format("%d0%d", cluster.tenant_id, i + local.network_infra.addressing.worker_offset))
      ]
    )
  }

  ha_resources = merge([
    for name, cluster in local.enabled_ha_clusters : {
      for vm_id in local.cluster_vm_ids[name] : "vm:${vm_id}" => {
        state        = try(cluster.proxmox_ha.state, "started")
        failback     = !try(cluster.proxmox_ha.nofailback, true)
        max_restart  = try(cluster.proxmox_ha.max_restart, 1)
        max_relocate = try(cluster.proxmox_ha.max_relocate, 1)
        type         = "vm"
      }
    }
  ]...)

  ha_rules = {
    for name, cluster in local.enabled_ha_clusters :
    "${cluster.proxmox_ha.group_name}-nodes" => {
      type      = "node-affinity"
      resources = [for vm_id in local.cluster_vm_ids[name] : "vm:${vm_id}"]
      nodes = {
        for node in try(cluster.proxmox_ha.nodes, local.proxmox_infra.proxmox_nodes) :
        node => lookup(try(cluster.proxmox_ha.node_priorities, {}), node, 1)
      }
      strict = try(cluster.proxmox_ha.restricted, true)
    }
  }
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  username = "root@pam"
  password = data.sops_file.proxmox.data["pve_password"]
  insecure = true
}
EOF
}

inputs = {
  ha_resources = local.ha_resources
  ha_rules     = local.ha_rules
}
