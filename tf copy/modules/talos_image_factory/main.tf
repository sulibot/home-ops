terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

variable "version" {
  description = "Talos version (e.g., v1.8.2)"
  type        = string
}

variable "platform" {
  description = "Talos image platform (nocloud, metal, qemu, etc.)"
  type        = string
  default     = "nocloud"
}

variable "architecture" {
  description = "CPU architecture"
  type        = string
  default     = "amd64"
}

variable "extra_kernel_args" {
  description = "Additional kernel arguments for the generated image"
  type        = list(string)
  default     = []
}

variable "system_extensions" {
  description = "Talos official system extensions to embed"
  type        = list(string)
  default     = []
}

variable "patches" {
  description = "Advanced customization using JSON patch operations"
  type        = any
  default     = []
}

locals {
  factory_payload = {
    version      = var.version
    platform     = var.platform
    architecture = var.architecture
    customization = {
      extraKernelArgs = var.extra_kernel_args
      systemExtensions = {
        officialExtensions = var.system_extensions
      }
    }
    patches = var.patches
  }
}

data "http" "talos_factory" {
  url             = "https://factory.talos.dev/api/v1alpha1/image"
  method          = "POST"
  request_headers = { "Content-Type" = "application/json" }
  request_body    = jsonencode(local.factory_payload)
}

locals {
  factory_response = jsondecode(data.http.talos_factory.response_body)
  image_key        = "${var.platform}-${var.architecture}"
  image_url        = try(local.factory_response.artifacts[local.image_key].url, "")
  image_id         = try(local.factory_response.id, "")
}

output "image_url" {
  description = "Download URL of the generated Talos image"
  value       = local.image_url
}

output "image_id" {
  description = "Talos factory build ID"
  value       = local.image_id
}
