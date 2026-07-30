# NixOS LXC validating a PVE-host CephFS bind mount. The container receives
# no CephX key. The bind source must exist on every migration target.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra   = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  catalog         = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  guest           = local.catalog.services["nixfs-lxc"]
  common_space_id = "5348ae65-b9b1-406d-b9d4-1f9139933a37"
  common_path     = "/mnt/pve/content/users/projects/${local.common_space_id}"
  credentials     = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file    = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
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

  after_hook "reconcile_bind_mounts" {
    commands = ["apply"]
    execute = [
      "${get_terragrunt_dir()}/../reconcile-lxc-bind-mounts.sh",
      local.guest.node_name,
      tostring(local.guest.vm_id),
      "/mnt/pve/content/users/sulibot/Cloud",
      "/home/sulibot/Cloud",
      local.common_path,
      "/srv/common",
      "1888405477",
      "1888405477",
    ]
  }
}

inputs = {
  template_file_id = "resources:vztmpl/nixos-25.11-proxmox-lxc-x86_64.tar.xz"

  proxmox = {
    vm_datastore = local.guest.storage.vm_datastore
  }

  ssh_public_keys = [file(pathexpand("~/.ssh/id_ed25519.pub"))]

  containers = {
    (local.guest.hostname) = {
      vm_id        = local.guest.vm_id
      node_name    = local.guest.node_name
      hostname     = local.guest.hostname
      description  = "NixOS user-storage validation LXC"
      cpu_cores    = local.guest.sizing.cpu_cores
      memory_mb    = local.guest.sizing.memory_mb
      swap_mb      = local.guest.sizing.swap_mb
      disk_gb      = local.guest.sizing.disk_gb
      bridge       = local.guest.network.bridge
      vlan_id      = local.guest.network.vlan_id
      ipv4_address = local.guest.ipv4_cidr
      ipv4_gateway = local.guest.network.ipv4_gateway
      ipv6_address = local.guest.ipv6_cidr
      ipv6_gateway = local.guest.network.ipv6_gateway
      tags         = ["nixos", "lxc", "user-storage-validation"]
      # A privileged CT preserves the Kanidm numeric UID/GID across this
      # host bind mount. Use a VM for untrusted workloads; an unprivileged CT
      # requires an explicitly managed 1:1 idmap for every entitled UID/GID.
      unprivileged = false
      mount_points = [
        {
          volume = "/mnt/pve/content/users/sulibot/Cloud"
          path   = "/home/sulibot/Cloud"
          backup = false
        },
        {
          volume = local.common_path
          path   = "/srv/common"
          backup = false
        },
      ]
    }
  }
}
