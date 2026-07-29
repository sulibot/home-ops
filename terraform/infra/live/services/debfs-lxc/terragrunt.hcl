# Debian LXC validating a PVE-host CephFS bind mount. The container receives
# no CephX key and the bind-mounted content is excluded from vzdump.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  catalog       = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  kanidm_auth   = read_terragrunt_config(find_in_parent_folders("common/lxc-kanidm-auth.hcl")).locals
  guest         = local.catalog.services["debfs-lxc"]
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
  source = "../../../modules/proxmox_lxc_role"
}

inputs = {
  proxmox = {
    datastore_id = local.proxmox_infra.storage.datastore_id
    vm_datastore = local.guest.storage.vm_datastore
  }

  template = {
    download  = false
    url       = ""
    file_name = ""
    file_id   = local.catalog.lxc_defaults.template_file_id
  }

  dns_servers = ["10.255.0.11", "fd00:0:0:ffff::11"]

  containers = {
    (local.guest.hostname) = {
      vm_id           = local.guest.vm_id
      node_name       = local.guest.node_name
      hostname        = local.guest.hostname
      description     = "Debian user-storage validation LXC"
      tags            = ["debian", "lxc", "user-storage-validation"]
      # See the NixOS LXC note: privileged is the deliberate POSIX-ID
      # compatibility choice for this trusted bind-mount validation guest.
      unprivileged    = false
      cpu_cores       = local.guest.sizing.cpu_cores
      memory_mb       = local.guest.sizing.memory_mb
      swap_mb         = local.guest.sizing.swap_mb
      disk_gb         = local.guest.sizing.disk_gb
      bridge          = local.guest.network.bridge
      vlan_id         = local.guest.network.vlan_id
      ipv4_address    = local.guest.ipv4_cidr
      ipv4_gateway    = local.guest.network.ipv4_gateway
      ipv6_address    = local.guest.ipv6_cidr
      ipv6_gateway    = local.guest.network.ipv6_gateway
      ssh_public_keys = [file(pathexpand("~/.ssh/id_ed25519.pub"))]
      mount_points = [{
        volume = "/mnt/pve/content/users/sulibot/Cloud"
        path   = "/home/sulibot/Cloud"
        backup = false
      }]
    }
  }

  provision = {
    enabled            = true
    ssh_user           = "root"
    ssh_private_key    = file(pathexpand("~/.ssh/id_ed25519"))
    ssh_timeout        = "5m"
    wait_for_cloudinit = false
    commands = concat(
      [
        "apt-get update -qq",
        "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq acl attr",
      ],
      local.kanidm_auth.kanidm_unix_auth_commands,
    )
  }
}
