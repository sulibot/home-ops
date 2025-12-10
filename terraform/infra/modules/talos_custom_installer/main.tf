terraform {
  backend "local" {}

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
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
  description = "Talos version (e.g., v1.11.5)"
}

variable "official_extensions" {
  type        = list(string)
  description = "List of official system extensions (siderolabs/*)"
  default     = []
}

variable "custom_extensions" {
  type        = list(string)
  description = "List of custom system extension images"
  default     = []
}

variable "output_registry" {
  type        = string
  description = "Container registry to push the custom installer (e.g., ghcr.io/username/repo)"
}

locals {
  installer_tag = "${var.output_registry}:${var.talos_version}"

  # Only add custom extension flags (official extensions come from factory base installer)
  extension_flags = join(" ", [
    for ext in var.custom_extensions :
    "--system-extension-image ${ext}"
  ])

  # Generate factory schematic for official extensions
  factory_schematic_request = jsonencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.official_extensions
      }
    }
  })
}

# Build custom installer image using Talos imager
resource "null_resource" "build_installer" {
  triggers = {
    talos_version        = var.talos_version
    official_extensions  = join(",", var.official_extensions)
    custom_extensions    = join(",", var.custom_extensions)
    registry             = var.output_registry
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Create temp directory for output
      TEMP_DIR=$(mktemp -d)
      trap "rm -rf $TEMP_DIR" EXIT

      echo "Getting factory schematic ID for official extensions..."

      # Get factory schematic ID for official extensions
      SCHEMATIC_ID=$(curl -s "https://factory.talos.dev/schematics" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '${local.factory_schematic_request}' | \
        jq -r '.id')

      echo "Factory schematic ID: $SCHEMATIC_ID"
      echo "Building custom installer ${var.talos_version} with BIRD2 extension..."

      # Use factory installer with official extensions as base, add only custom extensions
      docker run --rm \
        -v "$TEMP_DIR:/out" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ghcr.io/siderolabs/imager:${var.talos_version} \
        installer \
        --arch amd64 \
        --platform metal \
        --base-installer-image factory.talos.dev/installer/$SCHEMATIC_ID:${var.talos_version} \
        ${local.extension_flags}

      # Load the built image and get the image reference
      LOADED_IMAGE=$(docker load < $TEMP_DIR/installer-amd64.tar | sed -n 's/^Loaded image: //p')

      # Tag and push
      docker tag "$LOADED_IMAGE" ${local.installer_tag}
      docker push ${local.installer_tag}

      echo "Custom installer pushed to ${local.installer_tag}"
    EOT
  }
}

output "installer_image" {
  value       = local.installer_tag
  description = "Custom installer image reference"
  depends_on  = [null_resource.build_installer]
}
