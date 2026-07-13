locals {
  # Source of truth: site.yaml -> site.json (scripts/sync-site-facts.sh).
  # This file is the Terraform-facing adapter; edit site.yaml, not here.
  site = jsondecode(file("${get_repo_root()}/site.json"))

  # Proxmox cluster nodes
  proxmox_nodes = keys(local.site.proxmox.nodes)

  # Primary node for initial operations
  proxmox_primary_node = local.site.proxmox.primary_node

  # Fully qualified hostnames
  proxmox_hostnames = {
    for name, node in local.site.proxmox.nodes : name => "${name}.${local.site.domain}"
  }

  # Management-plane API endpoint. Optional in site.yaml -- scripts/sync-site-facts.sh
  # materializes it from primary_node's mgmt_ip when absent; try() here is a
  # defensive fallback for the same derivation in case site.json is stale.
  api_endpoint = try(
    local.site.proxmox.api_endpoint,
    "https://${local.site.proxmox.nodes[local.site.proxmox.primary_node].mgmt_ip}:8006/api2/json",
  )

  # Management-network SSH addresses for direct node access (provisioners)
  ssh_hosts = {
    for name, node in local.site.proxmox.nodes : name => node.mgmt_ip
  }

  # Storage configuration
  storage = {
    datastore_id = "resources" # For ISO, snippets, cloud-init
    vm_datastore = "rbd-vm"    # For VM disks (Ceph RBD)
  }
}
