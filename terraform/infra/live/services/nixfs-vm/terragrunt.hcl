# NixOS VM validating direct, path-scoped CephFS access.
# First install:
#   nix run github:nix-community/nixos-anywhere -- \
#     --flake ./nix#nixfs-vm01 --build-on-remote root@10.200.0.203

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  catalog       = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  guest         = local.catalog.services["nixfs-vm"]
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF2
provider "sops" {}

data "sops_file" "secrets" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = "${local.proxmox_infra.api_endpoint}"
  username = "root@pam"
  password = data.sops_file.secrets.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}

terraform {
  backend "gcs" {}
}
EOF2
}

terraform {
  source = "../../../modules/proxmox_nixos_vm"
}

inputs = {
  vm_name = local.guest.hostname
  vm_id   = local.guest.vm_id

  proxmox = {
    node_name    = local.guest.node_name
    datastore_id = local.proxmox_infra.storage.datastore_id
    vm_datastore = local.guest.storage.vm_datastore
  }

  vm_resources = {
    cpu_cores = local.guest.sizing.cpu_cores
    memory_mb = local.guest.sizing.memory_mb
    disk_gb   = local.guest.sizing.disk_gb
  }

  network = {
    bridge       = local.guest.network.bridge
    vlan_id      = local.guest.network.vlan_id
    ipv4_address = local.guest.ipv4_cidr
    ipv4_gateway = local.guest.network.ipv4_gateway
  }

  ssh_public_key = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
}
