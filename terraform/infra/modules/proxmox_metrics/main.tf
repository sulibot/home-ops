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

resource "proxmox_metrics_server" "this" {
  for_each = var.metrics_servers

  name   = each.key
  server = each.value.server
  port   = each.value.port
  type   = each.value.type

  disable                           = try(each.value.disable, null)
  graphite_path                     = try(each.value.graphite_path, null)
  graphite_proto                    = try(each.value.graphite_proto, null)
  influx_api_path_prefix            = try(each.value.influx_api_path_prefix, null)
  influx_bucket                     = try(each.value.influx_bucket, null)
  influx_db_proto                   = try(each.value.influx_db_proto, null)
  influx_max_body_size              = try(each.value.influx_max_body_size, null)
  influx_organization               = try(each.value.influx_organization, null)
  influx_token                      = try(each.value.influx_token, null)
  influx_verify                     = try(each.value.influx_verify, null)
  mtu                               = try(each.value.mtu, null)
  opentelemetry_compression         = try(each.value.opentelemetry_compression, null)
  opentelemetry_headers             = try(each.value.opentelemetry_headers, null)
  opentelemetry_max_body_size       = try(each.value.opentelemetry_max_body_size, null)
  opentelemetry_path                = try(each.value.opentelemetry_path, null)
  opentelemetry_proto               = try(each.value.opentelemetry_proto, null)
  opentelemetry_resource_attributes = try(each.value.opentelemetry_resource_attributes, null)
  opentelemetry_timeout             = try(each.value.opentelemetry_timeout, null)
  opentelemetry_verify_ssl          = try(each.value.opentelemetry_verify_ssl, null)
  timeout                           = try(each.value.timeout, null)
}
