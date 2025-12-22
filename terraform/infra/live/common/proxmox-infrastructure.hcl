locals {
  # Proxmox cluster nodes
  proxmox_nodes = ["pve01", "pve02", "pve03"]

  # Primary node for initial operations
  proxmox_primary_node = "pve01"

  # Fully qualified hostnames
  proxmox_hostnames = {
    pve01 = "pve01.sulibot.com"
    pve02 = "pve02.sulibot.com"
    pve03 = "pve03.sulibot.com"
  }

  # Storage configuration
  storage = {
    datastore_id = "resources"  # For ISO, snippets, cloud-init
    vm_datastore = "rbd-vm"     # For VM disks (Ceph RBD)
  }
}
