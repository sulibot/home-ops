# Terragrunt configuration for NixOS build server
# Used for building Talos extensions and other packages

include "nixos_common" {
  path   = "../nixos-common.hcl"
  expose = true
}

locals {
  nixos_common = include.nixos_common.locals

  # VM specifics
  vm_id   = 10201
  vm_name = "nixos-build"

  # Network
  ipv4_address = "10.200.0.201"
  ipv4_gateway = "10.200.0.254"
  ipv6_address = "fd00:200::201"
  ipv6_gateway = "fd00:200::fffe"

}

inputs = {
  vm_id   = local.vm_id
  vm_name = local.vm_name

  network = {
    bridge       = local.nixos_common.bridge
    vlan_id      = local.nixos_common.vlan_id
    ipv4_address = local.ipv4_address
    ipv4_gateway = local.ipv4_gateway
    ipv6_address = local.ipv6_address
    ipv6_gateway = local.ipv6_gateway
    mtu          = 1500
    firewall     = false
  }

  vm_resources = {
    cpu_cores = 8
    memory_mb = 16384
    disk_gb   = 200
  }

  initial_packages = [
    "docker.io",
    "docker-compose",
    "build-essential",
    "git",
    "curl",
    "wget",
    "vim",
    "htop"
  ]

  tags = ["debian", "build", "development"]

  on_boot = true
}
