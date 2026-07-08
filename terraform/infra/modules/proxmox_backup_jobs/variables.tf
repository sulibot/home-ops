variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "backup_jobs" {
  description = "Proxmox cluster backup jobs keyed by job id."
  type = map(object({
    schedule                  = string
    storage                   = string
    all                       = optional(bool)
    bwlimit                   = optional(number)
    compress                  = optional(string)
    enabled                   = optional(bool)
    exclude_path              = optional(list(string))
    ionice                    = optional(number)
    lockwait                  = optional(number)
    mailnotification          = optional(string)
    mailto                    = optional(list(string))
    mode                      = optional(string)
    node                      = optional(string)
    notes_template            = optional(string)
    pbs_change_detection_mode = optional(string)
    pigz                      = optional(number)
    pool                      = optional(string)
    protected                 = optional(bool)
    prune_backups             = optional(map(string))
    repeat_missed             = optional(bool)
    script                    = optional(string)
    starttime                 = optional(string)
    stdexcludes               = optional(bool)
    stopwait                  = optional(number)
    tmpdir                    = optional(string)
    vmid                      = optional(list(string))
    zstd                      = optional(number)
    fleecing = optional(object({
      enabled = optional(bool)
      storage = optional(string)
    }))
    performance = optional(object({
      max_workers     = optional(number)
      pbs_entries_max = optional(number)
    }))
  }))
  default = {}
}
