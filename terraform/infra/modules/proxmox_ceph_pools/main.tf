terraform {
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.98.0, < 1.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3.0"
    }
  }
}

locals {
  managed_pools = {
    for name, pool in var.ceph_pools : name => pool
    if try(pool.managed, false)
  }
}

resource "proxmox_ceph_pool" "this" {
  for_each = local.managed_pools

  node_name = var.node_name
  name      = each.key

  add_storages      = try(each.value.add_storages, null)
  application       = try(each.value.application, null)
  crush_rule        = try(each.value.crush_rule, null)
  erasure_coding    = try(each.value.erasure_coding, null)
  force_destroy     = try(each.value.force_destroy, null)
  min_size          = try(each.value.min_size, null)
  pg_autoscale_mode = try(each.value.pg_autoscale_mode, null)
  pg_num            = try(each.value.pg_num, null)
  pg_num_min        = try(each.value.pg_num_min, null)
  remove_ecprofile  = try(each.value.remove_ecprofile, null)
  remove_storages   = try(each.value.remove_storages, null)
  size              = try(each.value.size, null)
  target_size       = try(each.value.target_size, null)
  target_size_ratio = try(each.value.target_size_ratio, null)
}
