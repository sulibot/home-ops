# This file contains the high-level definition for the 'sol' cluster.
# It is read by the terragrunt.hcl in the child directories (e.g., `nodes`).
#
# Proxmox infrastructure config (nodes, storage) is now centralized in:
# common/proxmox-infrastructure.hcl

locals {
  cluster_name   = "sol"  # Human-readable cluster name
  cluster_id     = 101    # Numeric cluster identifier
  controlplanes  = 3
  workers        = 3
  network = {
    bridge_public = "vmbr0"      # Legacy: used when use_sdn = false
    vlan_public   = 101          # Legacy: used when use_sdn = false
    bridge_mesh   = "vnet101"
    vlan_mesh     = 0
    public_mtu    = 1450         # Legacy: used when use_sdn = false
    mesh_mtu      = 8930
    use_sdn       = true         # Use SDN VNet (vnet101) with dynamic unnumbered BGP peering
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
