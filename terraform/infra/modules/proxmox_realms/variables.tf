variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "openid_realms" {
  description = "OpenID realms keyed by realm id."
  type = map(object({
    issuer_url        = string
    client_id         = string
    acr_values        = optional(string)
    audiences         = optional(string)
    autocreate        = optional(bool)
    comment           = optional(string)
    default           = optional(bool)
    groups_autocreate = optional(bool)
    groups_claim      = optional(string)
    groups_overwrite  = optional(bool)
    prompt            = optional(string)
    query_userinfo    = optional(bool)
    scopes            = optional(string)
    username_claim    = optional(string)
  }))
  default = {}
}
