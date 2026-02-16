# Common configuration for VMs on VLAN 200
locals {
  # Load infrastructure configurations (following existing pattern)
  proxmox_infra = read_terragrunt_config(find_in_parent_folders("common/proxmox-infrastructure.hcl")).locals
  network_infra = read_terragrunt_config(find_in_parent_folders("common/network-infrastructure.hcl")).locals
  credentials   = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file  = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)

  # Proxmox settings (defaults, can be overridden)
  proxmox_node     = "pve02"
  datastore_id     = local.proxmox_infra.storage.datastore_id
  vm_datastore     = local.proxmox_infra.storage.vm_datastore

  # Network defaults - VLAN 200
  bridge           = "vmbr0"
  vlan_id          = 200
  dns_servers      = [local.network_infra.dns_servers.ipv4, "2001:4860:4860::8888"]

  # SSH key
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com"
}

# Use the debian_vm module
terraform {
  source = "${get_repo_root()}/terraform/infra/modules/debian_vm"
}

# Generate provider configuration (following existing pattern)
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

# Common inputs
inputs = {
  proxmox = {
    node_name    = local.proxmox_node
    datastore_id = local.datastore_id
    vm_datastore = local.vm_datastore
  }

  dns_servers    = local.dns_servers
  ssh_public_key = local.ssh_public_key
}
