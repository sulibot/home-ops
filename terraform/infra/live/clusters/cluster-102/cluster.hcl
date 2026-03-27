# Cluster-102 scaffold (guarded by default).
# Flip `enabled` to true when intentionally activating this tenant.

locals {
  enabled          = false
  cluster_name     = "sol102"
  tenant_id        = 102
  cluster_id       = 102
  controlplanes    = 3
  workers          = 3
  talos_apply_mode = "staged_if_needing_reboot"

  network = {
    bridge_public = "vmbr0"
    vlan_public   = 102
    bridge_mesh   = "vnet102"
    vlan_mesh     = 0
    public_mtu    = 1450
    mesh_mtu      = 8930
    use_sdn       = true
  }

  proxmox_ha = {
    enabled      = true
    group_name   = "sol102-k8s"
    restricted   = true
    nofailback   = true
    state        = "started"
    max_restart  = 3
    max_relocate = 3
  }

  hardware_mappings = read_terragrunt_config(find_in_parent_folders("common/proxmox_hardware_mappings/terragrunt.hcl")).locals

  gpu_config = {
    enabled       = true
    mapping       = "intel-igpu-vf1"
    pcie          = true
    rombar        = false
    driver        = "xe"
    driver_params = {}
  }

  usb_config = []

  worker_configs = {
    for i in range(1, local.workers + 1) :
    format("%swk%02d", local.cluster_name, i) => {
      node_name = format("pve%02d", i)
      gpu_passthrough = (
        local.gpu_config.enabled &&
        can(local.hardware_mappings.pci_mapping_paths[local.gpu_config.mapping][format("pve%02d", i)])
        ) ? merge(
        local.gpu_config,
        {
          pci_address = local.hardware_mappings.pci_mapping_paths[local.gpu_config.mapping][format("pve%02d", i)]
        }
      ) : null
      usb = null
    }
  }

  node_overrides = local.worker_configs
}
