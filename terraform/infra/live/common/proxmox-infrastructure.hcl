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

  # Management-plane API endpoint (see site.yaml for why it points at pve02)
  api_endpoint = local.site.proxmox.api_endpoint

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
