variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "directory_storages" {
  description = "Directory storages keyed by storage id."
  type = map(object({
    path             = string
    content          = optional(set(string))
    create_base_path = optional(bool)
    create_subdirs   = optional(bool)
    disable          = optional(bool)
    nodes            = optional(set(string))
    preallocation    = optional(string)
    shared           = optional(bool)
    backups = optional(object({
      keep_all              = optional(bool)
      keep_daily            = optional(number)
      keep_hourly           = optional(number)
      keep_last             = optional(number)
      keep_monthly          = optional(number)
      keep_weekly           = optional(number)
      keep_yearly           = optional(number)
      max_protected_backups = optional(number)
    }))
  }))
  default = {}
}

variable "zfspool_storages" {
  description = "ZFS pool storages keyed by storage id."
  type = map(object({
    zfs_pool       = string
    blocksize      = optional(string)
    content        = optional(set(string))
    disable        = optional(bool)
    nodes          = optional(set(string))
    thin_provision = optional(bool)
  }))
  default = {}
}
