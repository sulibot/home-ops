locals {
  cluster = read_terragrunt_config("${get_terragrunt_dir()}/cluster.hcl")

  proxmox = {
    datastore_id = "resources"
    vm_datastore = "rbd-vm"
    node_primary = "pve01"
    nodes        = local.cluster.locals.proxmox_nodes
  }

  vm_defaults = {
    cpu_cores = 4
    memory_mb = 16384
    disk_gb   = 60
  }

  network = {
    bridge_mesh   = "vnet${local.cluster.locals.cluster_id}"
    vlan_mesh     = 0
    bridge_public = "vmbr0"
    vlan_public   = local.cluster.locals.cluster_id
  }

  # Generate control plane nodes
  controlplane_nodes = [
    for i in range(local.cluster.locals.controlplanes) : {
      name          = format("%scp0%02d", local.cluster.locals.cluster_name, 10 + i + 1)
      node_name     = local.cluster.locals.proxmox_nodes[i % length(local.cluster.locals.proxmox_nodes)]
      vm_id         = local.cluster.locals.cluster_id * 1000 + 10 + i + 1
      ip_suffix     = 10 + i + 1
      ipv6_public   = format("fd00:%d::%d/64", local.cluster.locals.cluster_id, 10 + i + 1)
      ipv4_public   = format("10.%d.0.%d/24", local.cluster.locals.cluster_id, 10 + i + 1)
    }
  ]

  # Generate worker nodes
  worker_nodes = [
    for i in range(local.cluster.locals.workers) : {
      name          = format("%swk0%02d", local.cluster.locals.cluster_name, 20 + i + 1)
      node_name     = local.cluster.locals.proxmox_nodes[i % length(local.cluster.locals.proxmox_nodes)]
      vm_id         = local.cluster.locals.cluster_id * 1000 + 20 + i + 1
      ip_suffix     = 20 + i + 1
      ipv6_public   = format("fd00:%d::%d/64", local.cluster.locals.cluster_id, 20 + i + 1)
      ipv4_public   = format("10.%d.0.%d/24", local.cluster.locals.cluster_id, 20 + i + 1)
    }
  ]

  # Combine all nodes and apply overrides by name
  nodes = [
    for node in concat(local.controlplane_nodes, local.worker_nodes) :
    merge(node, lookup(local.cluster.locals.node_overrides, node.name, {}))
  ]
}

inputs = {
  proxmox      = local.proxmox
  vm_defaults  = local.vm_defaults
  network      = local.network
  nodes        = local.nodes
}
