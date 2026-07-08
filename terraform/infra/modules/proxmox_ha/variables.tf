variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "ha_resources" {
  description = "HA resources keyed by resource ID, for example vm:101011."
  type = map(object({
    state        = optional(string)
    failback     = optional(bool)
    group        = optional(string)
    comment      = optional(string)
    max_relocate = optional(number)
    max_restart  = optional(number)
    type         = optional(string)
  }))
  default = {}
}

variable "ha_rules" {
  description = "HA rules keyed by rule name."
  type = map(object({
    type      = string
    resources = set(string)
    affinity  = optional(string)
    comment   = optional(string)
    disable   = optional(bool)
    nodes     = optional(map(number))
    strict    = optional(bool)
  }))
  default = {}
}
