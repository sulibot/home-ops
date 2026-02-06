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

  # ---------------------------------------------------------------------------
  # Reference shared Proxmox hardware mappings so clusters can resolve PCI IDs
  # without hardcoding them inline.
  hardware_mappings = read_terragrunt_config(find_in_parent_folders("common/proxmox_hardware_mappings/terragrunt.hcl")).locals

  # GPU Configuration to apply to all worker nodes
  # Requires Proxmox kernel 6.17.4-2-pve (or 6.14.8-2-pve) with i915-sriov-dkms
  # Kernel 6.17.2-2-pve has VFIO_MAP_DMA regression - avoid that version
  gpu_config = {
    enabled     = true
    mapping     = "intel-igpu-vf1"
    pcie        = true
    rombar      = false
    driver      = "i915"
    driver_params = {
      "enable_display" = "0"      # Disable display for compute-only (headless GPU)
      "enable_guc"     = "3"      # Enable GuC/HuC firmware for compute execution
      "force_probe"    = "*"      # Force driver to probe all Intel iGPUs (including Alderlake)
    }
  }

  # USB configuration for a specific worker node (disabled)
  usb_config = []

  # Dynamically generate node overrides for all worker nodes.
  # This avoids hardcoding and makes the configuration scalable.
  # - Workers get GPU only if a mapping exists for their PVE node (pve03 has no SR-IOV)
  # - Worker #2 (`solwk02`) gets the USB passthrough, matching the previous setup.
  # - Workers are pinned to pve01, pve02, etc. sequentially.
  worker_configs = {
    for i in range(1, local.workers + 1) :
    format("%swk%02d", local.cluster_name, i) => {
      node_name = format("pve%02d", i)
      # Only enable GPU passthrough if:
      # 1. gpu_config.enabled is true
      # 2. A PCI mapping exists for this node (e.g., pve03 has no SR-IOV support)
      gpu_passthrough = (
        local.gpu_config.enabled &&
        can(local.hardware_mappings.pci_mapping_paths[local.gpu_config.mapping][format("pve%02d", i)])
      ) ? merge(
        local.gpu_config,
        {
          pci_address = local.hardware_mappings.pci_mapping_paths[local.gpu_config.mapping][format("pve%02d", i)]
        }
      ) : null
      # USB passthrough disabled
      usb = null
    }
  }

  node_overrides = local.worker_configs
}
