terraform {
  backend "local" {}

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7.0"
    }
  }
}

variable "region" {
  type        = string
  description = "Region identifier (injected by root terragrunt)"
  default     = "home-lab"
}

variable "talos_extra_kernel_args" {
  type        = list(string)
  description = "Talos kernel arguments"
}

variable "talos_system_extensions" {
  type        = list(string)
  description = "Talos official system extensions"
}

variable "talos_custom_extensions" {
  type        = list(string)
  description = "Talos custom system extensions"
  default     = []
}

locals {
  # Build customization object conditionally
  customization = {
    extraKernelArgs = var.talos_extra_kernel_args
    systemExtensions = {
      officialExtensions = var.talos_system_extensions
    }
    customExtensions = length(var.talos_custom_extensions) > 0 ? [
      for ext in var.talos_custom_extensions : {
        image = ext
      }
    ] : null
    security = length(var.talos_custom_extensions) > 0 ? {
      allow-unsigned-extensions = true
    } : null
  }

  # Remove null values for clean YAML output
  customization_clean = {
    for k, v in local.customization : k => v if v != null
  }
}

# Generate install schematic with full extensions
resource "talos_image_factory_schematic" "install" {
  schematic = yamlencode({
    customization = local.customization_clean
  })
}

output "schematic_id" {
  value       = talos_image_factory_schematic.install.id
  description = "Install schematic ID for factory installer URL"
}
