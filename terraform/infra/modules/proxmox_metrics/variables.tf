variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "metrics_servers" {
  description = "Proxmox metrics servers keyed by server name."
  type = map(object({
    server                            = string
    port                              = number
    type                              = string
    disable                           = optional(bool)
    graphite_path                     = optional(string)
    graphite_proto                    = optional(string)
    influx_api_path_prefix            = optional(string)
    influx_bucket                     = optional(string)
    influx_db_proto                   = optional(string)
    influx_max_body_size              = optional(number)
    influx_organization               = optional(string)
    influx_token                      = optional(string)
    influx_verify                     = optional(bool)
    mtu                               = optional(number)
    opentelemetry_compression         = optional(string)
    opentelemetry_headers             = optional(string)
    opentelemetry_max_body_size       = optional(number)
    opentelemetry_path                = optional(string)
    opentelemetry_proto               = optional(string)
    opentelemetry_resource_attributes = optional(string)
    opentelemetry_timeout             = optional(number)
    opentelemetry_verify_ssl          = optional(bool)
    timeout                           = optional(number)
  }))
  default = {}
}
