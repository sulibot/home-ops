locals {
  versions          = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/versions.hcl").locals
  app_versions      = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/application-versions.hcl").locals
  install_schematic = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/install-schematic.hcl").locals
  network_infra     = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/network-infrastructure.hcl").locals
  proxmox_infra     = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/proxmox-infrastructure.hcl").locals
  ipv6_prefixes     = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/ipv6-prefixes.hcl").locals

  # Default safe apply behavior for runtime Talos updates.
  talos_apply_mode_default = "staged_if_needing_reboot"

  # Artifact handoff files are written by live/artifacts/* stacks after apply.
  artifacts_registry_catalog_path  = "${get_repo_root()}/terraform/infra/live/clusters/_shared/artifacts-registry.json"
  artifacts_schematic_catalog_path = "${get_repo_root()}/terraform/infra/live/clusters/_shared/artifacts-schematic.json"

  artifacts_registry_catalog = fileexists(local.artifacts_registry_catalog_path) ? jsondecode(file(local.artifacts_registry_catalog_path)) : {
    talos_image_file_ids = {
      pve01 = "resources:iso/mock-talos-image.iso"
    }
    talos_image_file_name = "mock-talos-image.iso"
    talos_image_id        = "mock-schematic-id"
    talos_version         = local.versions.talos_version
    kubernetes_version    = local.versions.kubernetes_version
    generated_at          = "mock"
  }

  artifacts_schematic_catalog = fileexists(local.artifacts_schematic_catalog_path) ? jsondecode(file(local.artifacts_schematic_catalog_path)) : {
    schematic_id = "mock-schematic-id"
    generated_at = "mock"
  }

  vm_sizing = {
    control_plane = {
      cpu_cores = 4
      memory_mb = 8192
      disk_gb   = 60
      swap_disk_gb = 8
    }
    worker = {
      cpu_cores = 6
      memory_mb = 16384
      disk_gb   = 80
      swap_disk_gb = 8
    }
  }

  talos_defaults = {
    install_disk          = "/dev/sda"
    install_wipe          = false
    enable_node_swap      = true
    kubelet_swap_behavior = "LimitedSwap"
    swap_swappiness       = 10
    swap_size             = "8GiB"
    ephemeral_max_size    = "50GiB"
  }
}
