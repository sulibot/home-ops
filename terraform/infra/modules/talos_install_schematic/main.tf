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

# Generate install schematic with full extensions
resource "talos_image_factory_schematic" "install" {
  schematic = yamlencode({
    customization = merge(
      {
        extraKernelArgs = var.talos_extra_kernel_args
        systemExtensions = {
          officialExtensions = var.talos_system_extensions
        }
      },
      length(var.talos_custom_extensions) > 0 ? {
        customExtensions = [
          for ext in var.talos_custom_extensions : {
            image = ext
          }
        ]
        security = {
          allow-unsigned-extensions = true
        }
      } : {}
    )
  })
}

output "schematic_id" {
  value       = talos_image_factory_schematic.install.id
  description = "Install schematic ID for factory installer URL"
}
