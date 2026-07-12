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

  # Management-plane API endpoint (internal address; avoids public DNS/CF path)
  api_endpoint = "https://10.10.0.1:8006/api2/json"

  # Management-network SSH addresses for direct node access (provisioners)
  ssh_hosts = {
    pve01 = "10.10.0.1"
    pve02 = "10.10.0.2"
    pve03 = "10.10.0.3"
  }

  # Storage configuration
  storage = {
    datastore_id = "resources" # For ISO, snippets, cloud-init
    vm_datastore = "rbd-vm"    # For VM disks (Ceph RBD)
  }
}
