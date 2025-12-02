# This file contains the high-level definition for the 'sol' cluster.
# It is read by the terragrunt.hcl in the child directories (e.g., `nodes`).

locals {
  cluster_name   = "sol"  # Human-readable cluster name
  cluster_id     = 101    # Numeric cluster identifier
  controlplanes  = 3
  workers        = 3
  proxmox_nodes  = ["pve01", "pve02", "pve03"]
  storage_default = "rbd-vm"
  network = {
    bridge_public = "vmbr0"
    vlan_public   = 101
    bridge_mesh   = "vnet101"
    vlan_mesh     = 0
    public_mtu    = 1500
    mesh_mtu      = 8930
  }
  node_overrides = {
    # GPU passthrough for all worker nodes
    # All Proxmox hosts have Intel iGPUs at PCI address 0000:00:02.0
    "solwk01" = {
      node_name = "pve01"
      gpu_passthrough = {
        pci_address = "0000:00:02.0"  # Intel UHD Graphics 730 (AlderLake-S GT1)
        pcie        = true
        rombar      = true
        x_vga       = false
      }
    }
    "solwk02" = {
      node_name = "pve02"
      gpu_passthrough = {
        pci_address = "0000:00:02.0"  # Intel UHD Graphics 730 (AlderLake-S GT1)
        pcie        = true
        rombar      = true
        x_vga       = false
      }
    }
    "solwk03" = {
      node_name = "pve03"
      gpu_passthrough = {
        pci_address = "0000:00:02.0"  # Intel UHD Graphics 630 (CometLake-S GT2)
        pcie        = true
        rombar      = true
        x_vga       = false
      }
    }
  }
}
