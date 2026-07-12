# Pilot NixOS VM: x86_64 build server. Terraform boots a Debian bootstrap
# image; first install is one manual command (printed as the
# install_command output):
#   nix run github:nix-community/nixos-anywhere -- --flake ./nix#nixbuild01 --build-on-remote root@10.200.0.201
# After that: nixos-rebuild switch --flake ./nix#nixbuild01 --target-host root@10.200.0.201 --build-host root@10.200.0.201

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
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
  backend "local" {}
}
EOF2
}

terraform {
  source = "../../../modules/proxmox_nixos_vm"
}

inputs = {
  vm_name = "nixbuild01"
  vm_id   = 200201

  proxmox = {
    node_name    = "pve02"
    datastore_id = local.proxmox_infra.storage.datastore_id
    vm_datastore = local.proxmox_infra.storage.vm_datastore
  }

  vm_resources = {
    cpu_cores = 6
    memory_mb = 16384
    disk_gb   = 100
  }

  network = {
    bridge       = "vmbr0"
    vlan_id      = 200
    ipv4_address = "10.200.0.201/24"
    ipv4_gateway = "10.200.0.254"
  }

  ssh_public_key = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
}
