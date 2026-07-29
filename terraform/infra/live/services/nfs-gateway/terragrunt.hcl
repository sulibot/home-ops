# Two Debian NFS-Ganesha LXCs provide an active/passive NFSv4 endpoint for the
# canonical CephFS user tree. CephX material is deliberately installed by
# configure-ceph.sh, not passed through Terraform state.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  catalog       = read_terragrunt_config(find_in_parent_folders("common/lxc-service-catalog.hcl")).locals
  service       = local.catalog.services["nfs-gateway"]
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  node_ipv4     = [for name in sort(keys(local.service.instances)) : local.service.instances[name].ipv4]
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
    vm_datastore = local.service.storage.vm_datastore
  }

  template = {
    download  = false
    url       = ""
    file_name = ""
    file_id   = local.catalog.lxc_defaults.template_file_id
  }

  dns_servers = [local.catalog.site.dns_servers.ipv4, local.catalog.site.dns_servers.ipv6]

  containers = {
    for name, node in local.service.instances : name => {
      vm_id       = node.vm_id
      node_name   = node.node_name
      hostname    = node.hostname
      description = "CephFS NFS-Ganesha gateway; peer HA endpoint on tenant 200"
      tags        = ["cephfs", "debian", "ganesha", "lxc", "nfs"]
      # Keepalived must manage a floating address. These are trusted,
      # single-purpose infrastructure guests with path-limited CephX caps.
      unprivileged    = false
      protection      = true
      cpu_cores       = local.service.sizing.cpu_cores
      memory_mb       = local.service.sizing.memory_mb
      swap_mb         = local.service.sizing.swap_mb
      disk_gb         = local.service.sizing.disk_gb
      bridge          = local.service.network.bridge
      vlan_id         = local.service.network.vlan_id
      ipv4_address    = node.ipv4_cidr
      ipv4_gateway    = local.service.network.ipv4_gateway
      ipv6_address    = node.ipv6_cidr
      ipv6_gateway    = local.service.network.ipv6_gateway
      ssh_public_keys = [file(pathexpand("~/.ssh/id_ed25519.pub"))]
    }
  }

  provision = {
    enabled            = true
    ssh_user           = "root"
    ssh_private_key    = file(pathexpand("~/.ssh/id_ed25519"))
    ssh_timeout        = "8m"
    wait_for_cloudinit = false
    commands = [
      "install -m 0750 /dev/null /usr/local/sbin/nfs-gateway-provision",
      "printf '%s' '${filebase64("${get_terragrunt_dir()}/provision.sh")}' | base64 --decode > /usr/local/sbin/nfs-gateway-provision",
      "NFS_VIP4='${local.service.vip.ipv4}' NFS_VIP6='${local.service.vip.ipv6}' NFS_NODES4='${join(" ", local.node_ipv4)}' /usr/local/sbin/nfs-gateway-provision",
    ]
  }
}
