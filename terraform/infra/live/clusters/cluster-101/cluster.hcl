# This file contains the high-level definition for the 'sol' cluster.
# It is read by the terragrunt.hcl in the child directories (e.g., `nodes`).
#
# Proxmox infrastructure config (nodes, storage) is now centralized in:
# common/proxmox-infrastructure.hcl

locals {
  enabled          = true
  cluster_name     = "sol" # Human-readable cluster name
  tenant_id        = 101   # Universal tenant identifier
  cluster_id       = 101   # Compatibility alias for module inputs expecting cluster_id
  controlplanes    = 3
  workers          = 3
  talos_apply_mode = "staged_if_needing_reboot"
  network = {
    bridge_public = "vmbr0" # Legacy: used when use_sdn = false
    vlan_public   = 101     # Legacy: used when use_sdn = false
    bridge_mesh   = "vnet101"
    vlan_mesh     = 0
    public_mtu    = 1450 # Legacy: used when use_sdn = false
    mesh_mtu      = 8930
    use_sdn       = true # Use SDN VNet (vnet101) with dynamic unnumbered BGP peering
  }

  proxmox_ha = {
    enabled      = true
    group_name   = "sol-k8s"
    restricted   = true
    nofailback   = true
    state        = "started"
    max_restart  = 3
    max_relocate = 3
  }

  # ---------------------------------------------------------------------------
  # Reference shared Proxmox hardware mappings so clusters can resolve PCI IDs
  # without hardcoding them inline.
  hardware_mappings = read_terragrunt_config(find_in_parent_folders("common/proxmox_hardware_mappings/terragrunt.hcl")).locals

  # GPU Configuration to apply to all worker nodes
  # Uses Xe driver (official Siderolabs extension) for newer Intel GPUs with SR-IOV
  # Kernel arg xe.force_probe=4680 is set in install-schematic.hcl for Alder Lake-S GT1 VF
  gpu_config = {
    enabled  = true
    mappings = [for vf in range(1, 8) : format("intel-igpu-vf%d", vf)]
    pcie     = true
    rombar   = false
    driver   = "xe"
    # No driver_params needed - xe.force_probe kernel arg handles GPU initialization
    driver_params = {}
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
      gpu_passthrough = local.gpu_config.enabled && length([
        for mapping in local.gpu_config.mappings :
        local.hardware_mappings.pci_mapping_paths[mapping][format("pve%02d", i)]
        if can(local.hardware_mappings.pci_mapping_paths[mapping][format("pve%02d", i)])
        ]) > 0 ? {
        pci_address = [
          for mapping in local.gpu_config.mappings :
          local.hardware_mappings.pci_mapping_paths[mapping][format("pve%02d", i)]
          if can(local.hardware_mappings.pci_mapping_paths[mapping][format("pve%02d", i)])
        ][0]
        pci_addresses = [
          for mapping in local.gpu_config.mappings :
          local.hardware_mappings.pci_mapping_paths[mapping][format("pve%02d", i)]
          if can(local.hardware_mappings.pci_mapping_paths[mapping][format("pve%02d", i)])
        ]
        pcie   = local.gpu_config.pcie
        rombar = local.gpu_config.rombar
      } : null
      # USB passthrough disabled
      usb = null
    }
  }

  node_overrides = local.worker_configs
}
