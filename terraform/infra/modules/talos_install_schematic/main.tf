terraform {
  backend "local" {}

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.0"
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

# Generate install schematic with official extensions only
# NOTE: Image Factory schematics do NOT support custom/third-party extensions
# Custom extensions like FRR must be added via overlays or custom installer images
resource "talos_image_factory_schematic" "install" {
  schematic = yamlencode({
    customization = {
      extraKernelArgs = var.talos_extra_kernel_args
      systemExtensions = {
        officialExtensions = var.talos_system_extensions
      }
    }
  })
}

output "schematic_id" {
  value       = talos_image_factory_schematic.install.id
  description = "Install schematic ID for factory installer URL"
}
