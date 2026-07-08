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

resource "proxmox_haresource" "this" {
  for_each = var.ha_resources

  resource_id  = each.key
  state        = try(each.value.state, null)
  failback     = try(each.value.failback, null)
  group        = try(each.value.group, null)
  comment      = try(each.value.comment, null)
  max_relocate = try(each.value.max_relocate, null)
  max_restart  = try(each.value.max_restart, null)
  type         = try(each.value.type, null)
}

resource "proxmox_harule" "this" {
  for_each = var.ha_rules

  rule      = each.key
  type      = each.value.type
  resources = each.value.resources

  affinity = try(each.value.affinity, null)
  comment  = try(each.value.comment, null)
  disable  = try(each.value.disable, null)
  nodes    = try(each.value.nodes, null)
  strict   = try(each.value.strict, null)

  depends_on = [proxmox_haresource.this]
}
