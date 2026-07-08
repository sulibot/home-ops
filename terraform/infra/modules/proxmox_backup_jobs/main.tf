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

resource "proxmox_backup_job" "this" {
  for_each = var.backup_jobs

  id       = each.key
  schedule = each.value.schedule
  storage  = each.value.storage

  all                       = try(each.value.all, null)
  bwlimit                   = try(each.value.bwlimit, null)
  compress                  = try(each.value.compress, null)
  enabled                   = try(each.value.enabled, null)
  exclude_path              = try(each.value.exclude_path, null)
  ionice                    = try(each.value.ionice, null)
  lockwait                  = try(each.value.lockwait, null)
  mailnotification          = try(each.value.mailnotification, null)
  mailto                    = try(each.value.mailto, null)
  mode                      = try(each.value.mode, null)
  node                      = try(each.value.node, null)
  notes_template            = try(each.value.notes_template, null)
  pbs_change_detection_mode = try(each.value.pbs_change_detection_mode, null)
  pigz                      = try(each.value.pigz, null)
  pool                      = try(each.value.pool, null)
  protected                 = try(each.value.protected, null)
  prune_backups             = try(each.value.prune_backups, null)
  repeat_missed             = try(each.value.repeat_missed, null)
  script                    = try(each.value.script, null)
  starttime                 = try(each.value.starttime, null)
  stdexcludes               = try(each.value.stdexcludes, null)
  stopwait                  = try(each.value.stopwait, null)
  tmpdir                    = try(each.value.tmpdir, null)
  vmid                      = try(each.value.vmid, null)
  zstd                      = try(each.value.zstd, null)
  fleecing                  = try(each.value.fleecing, null)
  performance               = try(each.value.performance, null)
}
