# Terragrunt configuration for Kanidm01 identity server (Master)
# Deployed on pve01

include "nixos_common" {
  path   = "../nixos-common.hcl"
  expose = true
}

locals {
  nixos_common = include.nixos_common.locals

  # VM specifics
  vm_id   = 10211
  vm_name = "kanidm01"

  # Network
  ipv4_address = "10.200.0.211"
  ipv4_gateway = "10.200.0.254"
  ipv6_address = "fd00:200::211"
  ipv6_gateway = "fd00:200::fffe"

}

inputs = {
  vm_id   = local.vm_id
  vm_name = local.vm_name

  # Override: Deploy on pve01
  proxmox = {
    node_name    = "pve01"
    datastore_id = local.nixos_common.datastore_id
    vm_datastore = local.nixos_common.vm_datastore
  }

  network = {
    bridge       = local.nixos_common.bridge
    vlan_id      = local.nixos_common.vlan_id
    ipv4_address = local.ipv4_address
    ipv4_gateway = local.ipv4_gateway
    ipv6_address = local.ipv6_address
    ipv6_gateway = local.ipv6_gateway
    mtu          = 1500
    firewall     = true
  }

  vm_resources = {
    cpu_cores = 2
    memory_mb = 2048
    disk_gb   = 40
  }

  initial_packages = ["curl", "wget", "vim"]

  tags = ["debian", "kanidm", "identity", "master"]

  on_boot = true
}
