variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "accounts" {
  description = "ACME accounts keyed by account name."
  type = map(object({
    contact   = string
    directory = optional(string)
    tos       = optional(string)
  }))
  default = {}
}

variable "dns_plugins" {
  description = "ACME DNS plugins keyed by plugin name."
  type = map(object({
    api              = string
    disable          = optional(bool)
    validation_delay = optional(number)
  }))
  default = {}
}
