# This file contains the high-level definition for the 'sol' cluster.
# It is read by the terragrunt.hcl in the child directories (e.g., `nodes`).

locals {
  cluster_name   = "sol"
  cluster_id     = 101
  controlplanes  = 3
  workers        = 3
  proxmox_nodes  = ["pve01", "pve02", "pve03"]
  storage_default = "rbd-vm"
  network = {
    bridge_public = "vmbr0"
    vlan_public   = 101
    bridge_mesh   = "vnet101"
    vlan_mesh     = 0
  }
  node_overrides = {
    # Example: give a specific node more memory
    # "sol-wk01" = { memory_mb = 32768 }
  }
}
