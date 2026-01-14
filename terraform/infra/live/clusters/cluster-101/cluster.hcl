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
    # Pin worker nodes to specific Proxmox hosts
    # GPU passthrough DISABLED - uncomment gpu_passthrough blocks below to re-enable
    "solwk01" = {
      node_name = "pve01"
      # gpu_passthrough = {
      #   pci_address = "0000:00:02.0"  # Intel iGPU PCI address (find with: lspci | grep VGA)
      #   pcie        = true            # PCIe passthrough mode (recommended)
      #   rombar      = false           # Disable ROM BAR for iGPU (required for Intel)
      #   x_vga       = false           # Not primary VGA (keeps serial console accessible)
      #   driver      = "i915"          # Optional: driver hint (defaults to i915 if omitted)
      #   driver_params = {             # Optional: override default params
      #     "enable_display" = "0"      # Disable display to prevent boot hang
      #     "enable_guc"     = "3"      # Enable GuC/HuC firmware
      #     "force_probe"    = "*"      # Probe all Intel GPUs
      #   }
      # }
    }
    "solwk02" = {
      node_name = "pve02"
      # gpu_passthrough = {
      #   pci_address = "0000:00:02.0"
      #   pcie        = true
      #   rombar      = false
      #   x_vga       = false
      # }
    }
    "solwk03" = {
      node_name = "pve03"
      # gpu_passthrough = {
      #   pci_address = "0000:00:02.0"
      #   pcie        = true
      #   rombar      = false
      #   x_vga       = false
      # }
    }
  }
}
