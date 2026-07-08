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

resource "proxmox_storage_directory" "directory" {
  for_each = var.directory_storages

  id   = each.key
  path = each.value.path

  content          = try(each.value.content, null)
  create_base_path = try(each.value.create_base_path, null)
  create_subdirs   = try(each.value.create_subdirs, null)
  disable          = try(each.value.disable, null)
  nodes            = try(each.value.nodes, null)
  preallocation    = try(each.value.preallocation, null)
  shared           = try(each.value.shared, null)

  dynamic "backups" {
    for_each = try(each.value.backups, null) == null ? [] : [each.value.backups]
    content {
      keep_all              = try(backups.value.keep_all, null)
      keep_daily            = try(backups.value.keep_daily, null)
      keep_hourly           = try(backups.value.keep_hourly, null)
      keep_last             = try(backups.value.keep_last, null)
      keep_monthly          = try(backups.value.keep_monthly, null)
      keep_weekly           = try(backups.value.keep_weekly, null)
      keep_yearly           = try(backups.value.keep_yearly, null)
      max_protected_backups = try(backups.value.max_protected_backups, null)
    }
  }
}

resource "proxmox_storage_zfspool" "zfspool" {
  for_each = var.zfspool_storages

  id       = each.key
  zfs_pool = each.value.zfs_pool

  blocksize      = try(each.value.blocksize, null)
  content        = try(each.value.content, null)
  disable        = try(each.value.disable, null)
  nodes          = try(each.value.nodes, null)
  thin_provision = try(each.value.thin_provision, null)
}
