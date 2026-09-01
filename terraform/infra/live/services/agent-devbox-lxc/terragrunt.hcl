# Persistent NixOS coordinator for Codex CLI and Claude Code. Terraform owns
# the LXC envelope; nix/hosts/agent-devbox01 owns everything inside it.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  lxc_catalog   = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  devbox        = local.lxc_catalog.services["agent-devbox"]
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
  source = "../../../modules/proxmox_nixos_lxc"
}

inputs = {
  template_file_id = "resources:vztmpl/nixos-25.11-proxmox-lxc-x86_64.tar.xz"

  proxmox = {
    vm_datastore = local.devbox.storage.vm_datastore
  }

  ssh_public_keys = [file(pathexpand("~/.ssh/id_ed25519.pub"))]

  containers = {
    agent-devbox01 = {
      vm_id        = local.devbox.vm_id
      node_name    = local.devbox.node_name
      hostname     = local.devbox.hostname
      description  = "Persistent Codex CLI and Claude Code coordinator (configured by NixOS)"
      cpu_cores    = local.devbox.sizing.cpu_cores
      memory_mb    = local.devbox.sizing.memory_mb
      swap_mb      = local.devbox.sizing.swap_mb
      disk_gb      = local.devbox.sizing.disk_gb
      bridge       = local.devbox.network.bridge
      vlan_id      = local.devbox.network.vlan_id
      ipv4_address = local.devbox.ipv4_cidr
      ipv4_gateway = local.devbox.network.ipv4_gateway
      ipv6_address = local.devbox.ipv6_cidr
      ipv6_gateway = local.devbox.network.ipv6_gateway
      tags         = ["agent", "claude", "codex", "devbox", "lxc", "nixos"]
    }
  }
}
