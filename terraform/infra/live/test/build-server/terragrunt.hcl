include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/debian_test_vm"
}

locals {
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {}
}
EOF
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  username = "root@pam"
  password = data.sops_file.proxmox.data["pve_password"]
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
  }
}
EOF
}

inputs = {
  vm_name = "build-server"
  vm_id   = 10143

  proxmox = {
    node_name    = "pve02"
    datastore_id = local.proxmox_infra.storage.datastore_id
    vm_datastore = local.proxmox_infra.storage.vm_datastore
  }

  vm_resources = {
    cpu_cores = 8
    memory_mb = 16384
    disk_gb   = 200
  }

  network = {
    bridge       = "vnet101"
    mtu          = 1450
    ipv4_address = "10.101.0.43"
    ipv4_netmask = "255.255.255.0"
    ipv4_gateway = "10.101.0.254"
    ipv6_address = "fd00:101::43"
    ipv6_prefix  = 64
    ipv6_gateway = "fd00:101::fffe"
  }

  loopback = {
    ipv4 = "10.101.254.43"
    ipv6 = "fd00:101:fe::43"
  }

  dns_servers = [
    local.network_infra.dns_servers.ipv6,
    local.network_infra.dns_servers.ipv4
  ]

  # Your SSH public key for root access
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com"

  # No FRR needed for build server
  frr_config = null
}
