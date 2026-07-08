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

resource "proxmox_acme_account" "this" {
  for_each = var.accounts

  name      = each.key
  contact   = each.value.contact
  directory = try(each.value.directory, null)
  tos       = try(each.value.tos, null)

  lifecycle {
    ignore_changes = [contact]
  }
}

resource "proxmox_acme_dns_plugin" "this" {
  for_each = var.dns_plugins

  plugin           = each.key
  api              = each.value.api
  disable          = try(each.value.disable, null)
  validation_delay = try(each.value.validation_delay, null)

  lifecycle {
    ignore_changes = [data]
  }
}
