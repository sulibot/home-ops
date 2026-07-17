# This file contains the high-level definition for the 'sol' cluster.
# It is read by the terragrunt.hcl in the child directories (e.g., `nodes`).
#
# Proxmox infrastructure config (nodes, storage) is now centralized in:
# common/proxmox-infrastructure.hcl

locals {
  # ── Cluster contract (required by clusters/_shared/units templates) ────────
  enabled             = true
  cluster_name        = "sol"          # Human-readable cluster name
  cluster_id          = 101            # Canonical cluster identity: state paths, output dirs, naming
  tenant_id           = 101            # Network tenancy: 10.<tenant>.x.x / fd00:<tenant>:: / vnet<tenant> (equals cluster_id unless segments ever diverge)
  bootstrap_node_ipv4 = "10.101.0.11"  # First control-plane node; used by kubeconfig/talosconfig refresh hooks
  kubernetes_api_host = "fd00:101::10" # API endpoint host controllers pin to (VIP on VM clusters, node IP on metal)
  talos_apply_mode    = "staged_if_needing_reboot"

  # ENG-14: candidate kube-vip BGP anycast replacement for the fragile Talos
  # floating VIP. The native Talos VIP remains enabled for the proof phase;
  # do not remove it until pve01/pve02/pve03 all prefer their local CP route
  # and the normal kubeconfig path is verified.
  kube_vip_bgp_anycast = {
    enabled              = true
    vip                  = "fd00:101::10"
    image                = "ghcr.io/kube-vip/kube-vip:v1.1.2"
    interface            = "lo"
    health_check_address = "https://localhost:6443/livez"
    health_check_ca_path = "/etc/kubernetes/pki/ca.crt"
  }

  talos_logging = {
    enabled  = true
    endpoint = "tcp://127.0.0.1:1514"
  }

  # ── VM-platform sizing (consumed by the compute provisioning unit) ─────────
  controlplanes = 3
  workers       = 3
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
    nodes        = ["pve01", "pve02"]
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
