terraform {
  # Backend configuration will be injected by Terragrunt
  backend "local" {}

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.86.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
  }
}

variable "region" {
  type        = string
  description = "Region identifier (injected by root terragrunt)"
  default     = "home-lab"
}

variable "talos_version" {
  type        = string
  description = "Talos release (e.g., v1.8.2)"
}

variable "talos_platform" {
  type        = string
  default     = "nocloud"
  description = "Talos image platform"
}

variable "talos_architecture" {
  type        = string
  default     = "amd64"
  description = "Talos image architecture"
}

variable "talos_extra_kernel_args" {
  type        = list(string)
  default     = []
  description = "Additional Talos kernel arguments"
}

variable "talos_system_extensions" {
  type        = list(string)
  default     = []
  description = "Talos official system extensions"
}

variable "talos_patches" {
  type        = any
  default     = []
  description = "JSON patch ops for Talos customization"
}

variable "talos_custom_extensions" {
  type        = list(string)
  default     = []
  description = "Talos custom system extensions (container images)"
}

variable "allow_unsigned_extensions" {
  type        = bool
  default     = false
  description = "Allow unsigned Talos extensions"
}

variable "proxmox_datastore_id" {
  type        = string
  description = "Proxmox datastore to upload the image to"
}

variable "proxmox_node_names" {
  type        = list(string)
  description = "Proxmox nodes that receive the upload"
}

variable "file_name_prefix" {
  type        = string
  default     = "talos"
  description = "Prefix for uploaded image name"
}

# Create Talos factory schematic using official provider
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      extraKernelArgs = var.talos_extra_kernel_args
      systemExtensions = {
        officialExtensions = var.talos_system_extensions
        customExtensions   = [for image in var.talos_custom_extensions : { image = image }]
        security = {
          "allow-unsigned-extensions" = var.allow_unsigned_extensions
        }
      }
    }
  })
}

locals {
  # Determine the image format path based on platform
  # See: https://github.com/siderolabs/image-factory
  # Using ISO format for nocloud to ensure proper UEFI boot support
  image_format_map = {
    "nocloud" = "nocloud-${var.talos_architecture}.iso"
    "metal"   = "metal-${var.talos_architecture}.raw.xz"
    "aws"     = "aws-${var.talos_architecture}.raw.xz"
    "azure"   = "azure-${var.talos_architecture}.raw.xz"
    "gcp"     = "gcp-${var.talos_architecture}.raw.xz"
  }
  image_format = lookup(local.image_format_map, var.talos_platform, "nocloud-${var.talos_architecture}.iso")

  # Construct download URL using schematic ID from official resource
  # Format: https://factory.talos.dev/image/{schematic_id}/{version}/{format}
  image_url = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/${var.talos_version}/${local.image_format}"

  # Use .iso extension for nocloud ISO images, .img for raw images
  image_extension = var.talos_platform == "nocloud" ? "iso" : "img"
  # Include schematic ID in filename for content-addressable caching
  # Proxmox will skip re-downloading if a file with this exact name already exists
  image_name = "${var.file_name_prefix}-${talos_image_factory_schematic.this.id}.${local.image_extension}"
}

# Direct download to Proxmox datastore from Talos Factory URL
# The provider checks if the file already exists in the datastore by filename
# If found with same name, it skips the download entirely
# This provides automatic caching based on the content-addressable schematic ID
resource "proxmox_virtual_environment_file" "uploaded" {
  for_each = toset(var.proxmox_node_names)

  content_type = "iso"
  datastore_id = var.proxmox_datastore_id
  node_name    = each.value

  source_file {
    path      = local.image_url
    file_name = local.image_name
  }

  # Protect ISO from accidental destruction during rebuilds
  lifecycle {
    prevent_destroy = true
  }
}

output "talos_image_id" {
  value       = talos_image_factory_schematic.this.id
  description = "Talos factory schematic ID"
}

output "talos_image_file_ids" {
  value       = { for k, v in proxmox_virtual_environment_file.uploaded : k => v.id }
  description = "Map of node name to Proxmox file ID for the Talos image"
}

output "talos_image_file_name" {
  value       = local.image_name
  description = "Filename stored in Proxmox"
}

output "talos_version" {
  value       = var.talos_version
  description = "Talos version used for this image"
}

output "kubernetes_version" {
  value       = "v1.31.4"  # Default K8s version for Talos v1.8.2
  description = "Recommended Kubernetes version for this Talos version"
}
