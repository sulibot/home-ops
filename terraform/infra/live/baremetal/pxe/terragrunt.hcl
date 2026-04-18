include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  versions          = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/common/versions.hcl").locals
  schematic_catalog = read_terragrunt_config("${get_repo_root()}/terraform/infra/live/clusters/_shared/context.hcl").locals.artifacts_schematic_catalog
  output_dir        = "${get_repo_root()}/tmp/pxe/routeros-usb/proxmox"
  ipxe_efi_url      = "https://boot.ipxe.org/x86_64-efi/ipxe.efi"
  snponly_efi_url   = "https://boot.ipxe.org/x86_64-efi/snponly.efi"

  host_profiles = {
    luna01 = {
      hostname        = "luna01"
      script_name     = "luna01.ipxe"
      description     = "Boot Talos for luna01"
      mac_address     = "00:E0:67:25:96:C8"
      talos_enabled   = true
      proxmox_enabled = true
    }
  }
}

terraform {
  source = "../../../modules/pxe_assets"

  after_hook "sync_routeros_assets" {
    commands = ["apply"]
    execute = [
      "bash",
      "-lc",
      "cd ${get_repo_root()} && export PATH=\"/opt/homebrew/bin:$PATH\" && export SOPS_AGE_KEY_FILE=\"${get_env("SOPS_AGE_KEY_FILE", "$HOME/.config/sops/age/keys.txt")}\" && export ASSET_DIR=\"${local.output_dir}\" && export IPXE_EFI_URL=\"${local.ipxe_efi_url}\" && export SNPONLY_EFI_URL=\"${local.snponly_efi_url}\" && ./scripts/routeros-sync-pxe.sh",
    ]
  }
}

inputs = {
  output_dir   = local.output_dir
  cluster_name = "luna"

  # RouterOS hosts stage-1 iPXE files from USB/TFTP. Stage-2 can still chain to
  # public Talos infrastructure so the lab is recoverable even if local infra is
  # wiped.
  talos_boot_entry_url   = "https://pxe.factory.talos.dev/pxe/${local.schematic_catalog.schematic_id}/${local.versions.talos_version}/metal-amd64"
  proxmox_boot_entry_url = "https://boot.netboot.xyz"

  host_profiles = local.host_profiles
}
