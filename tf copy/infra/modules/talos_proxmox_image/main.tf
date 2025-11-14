terraform {
  # Backend configuration will be injected by Terragrunt
  backend "local" {}

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
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

locals {
  # Build schematic payload for new API (only customization, not version/platform/arch)
  # Only include customization fields if they have values
  has_kernel_args = length(var.talos_extra_kernel_args) > 0
  has_extensions  = length(var.talos_system_extensions) > 0
  has_customization = local.has_kernel_args || local.has_extensions

  schematic_payload = local.has_customization ? {
    customization = merge(
      local.has_kernel_args ? { extraKernelArgs = var.talos_extra_kernel_args } : {},
      local.has_extensions ? {
        systemExtensions = {
          officialExtensions = var.talos_system_extensions
        }
      } : {}
    )
  } : {}

  # Determine the image format path based on platform
  # See: https://github.com/siderolabs/image-factory
  image_format_map = {
    "nocloud" = "nocloud-${var.talos_architecture}.raw.xz"
    "metal"   = "metal-${var.talos_architecture}.raw.xz"
    "aws"     = "aws-${var.talos_architecture}.raw.xz"
    "azure"   = "azure-${var.talos_architecture}.raw.xz"
    "gcp"     = "gcp-${var.talos_architecture}.raw.xz"
  }
  image_format = lookup(local.image_format_map, var.talos_platform, "nocloud-${var.talos_architecture}.raw.xz")
}

# Step 1: Create schematic and get ID
data "http" "talos_schematic" {
  url             = "https://factory.talos.dev/schematics"
  method          = "POST"
  request_headers = { "Content-Type" = "application/json" }
  request_body    = jsonencode(local.schematic_payload)
}

locals {
  schematic_response = jsondecode(data.http.talos_schematic.response_body)
  schematic_id       = local.schematic_response.id

  # Step 2: Construct download URL using schematic ID
  # Format: https://factory.talos.dev/image/{schematic_id}/{version}/{format}
  image_url = "https://factory.talos.dev/image/${local.schematic_id}/${var.talos_version}/${local.image_format}"

  image_dir  = "${path.root}/.talos-images"
  image_name = "${var.file_name_prefix}-${local.schematic_id}.img"
  image_path = "${local.image_dir}/${local.image_name}"

  # Check if image already exists locally to avoid redundant downloads
  # Since schematic IDs are content-addressable (same customization = same ID),
  # we can safely reuse cached images
  image_already_cached = fileexists(local.image_path)
}

resource "terraform_data" "download" {
  # Only download if the image doesn't already exist locally
  count = local.image_already_cached ? 0 : 1

  triggers_replace = {
    image_url  = local.image_url
    image_path = local.image_path
  }

  provisioner "local-exec" {
    when    = create
    command = "mkdir -p ${local.image_dir} && curl -L '${self.triggers_replace.image_url}' -o '${self.triggers_replace.image_path}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f '${self.triggers_replace.image_path}'"
  }
}

resource "proxmox_virtual_environment_file" "uploaded" {
  for_each = toset(var.proxmox_node_names)

  content_type = "iso"
  datastore_id = var.proxmox_datastore_id
  node_name    = each.value

  source_file {
    path      = local.image_path
    file_name = local.image_name
  }

  depends_on = [terraform_data.download]
}

output "talos_image_id" {
  value       = local.schematic_id
  description = "Talos factory schematic ID"
}

output "talos_image_file_ids" {
  value       = { for k, v in proxmox_virtual_environment_file.uploaded : k => v.id }
  description = "Map of node name to Proxmox file ID for the uploaded Talos image"
}

output "talos_image_file_name" {
  value       = local.image_name
  description = "Filename stored in Proxmox"
}
