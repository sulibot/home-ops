variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "node_name" {
  description = "Proxmox node used to dispatch Ceph pool API calls. Pools are cluster-wide."
  type        = string
}

variable "ceph_pools" {
  description = "Ceph pools eligible for Terraform management via bpg/proxmox. Only entries with managed=true create resources."
  type = map(object({
    managed           = optional(bool, false)
    add_storages      = optional(bool)
    application       = optional(string)
    crush_rule        = optional(string)
    erasure_coding    = optional(string)
    force_destroy     = optional(bool)
    min_size          = optional(number)
    pg_autoscale_mode = optional(string)
    pg_num            = optional(number)
    pg_num_min        = optional(number)
    remove_ecprofile  = optional(bool)
    remove_storages   = optional(bool)
    size              = optional(number)
    target_size       = optional(string)
    target_size_ratio = optional(number)
    owner             = optional(string)
    notes             = optional(string)
  }))
}
