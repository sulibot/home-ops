# Pilot NixOS LXC. Terraform only creates the container; system config is
# nix/hosts/nixtest01, deployed with:
#   nixos-rebuild switch --flake ./nix#nixtest01 --target-host root@10.200.0.202 --build-host root@10.200.0.202
# Template tarball: scripts/fetch-nixos-lxc-template.sh

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  nixtest_class = local.lxc_catalog.services.nixtest
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
  source = "../../../modules/proxmox_nixos_lxc"
}

inputs = {
  template_file_id = "resources:vztmpl/nixos-25.11-proxmox-lxc-x86_64.tar.xz"

  proxmox = {
    vm_datastore = local.nixtest_class.storage.vm_datastore
  }

  ssh_public_keys = [file(pathexpand("~/.ssh/id_ed25519.pub"))]

  containers = {
    nixtest01 = {
      vm_id        = local.nixtest_class.vm_id
      node_name    = local.nixtest_class.node_name
      hostname     = local.nixtest_class.hostname
      description  = "Pilot NixOS LXC (configured by nix/hosts/nixtest01)"
      cpu_cores    = local.nixtest_class.sizing.cpu_cores
      memory_mb    = local.nixtest_class.sizing.memory_mb
      swap_mb      = local.nixtest_class.sizing.swap_mb
      disk_gb      = local.nixtest_class.sizing.disk_gb
      bridge       = local.nixtest_class.network.bridge
      vlan_id      = local.nixtest_class.network.vlan_id
      ipv4_address = local.nixtest_class.ipv4_cidr
      ipv4_gateway = local.nixtest_class.network.ipv4_gateway
      ipv6_address = local.nixtest_class.ipv6_cidr
      ipv6_gateway = local.nixtest_class.network.ipv6_gateway
      tags         = ["nixos", "lxc", "pilot"]
    }
  }
}
