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

variable "kernel_args" {
  type        = list(string)
  description = "Extra kernel arguments to include in the installer"
  default     = []
}

locals {
  installer_tag = "${var.output_registry}:${var.talos_version}"

  # Build extension flags for ALL extensions (official + custom)
  # Official extensions should be passed as full image references with digests
  extension_flags = join(" ", [
    for ext in concat(var.official_extensions, var.custom_extensions) :
    "--system-extension-image ${ext}"
  ])

  # Generate factory schematic for kernel args only
  # Extensions are added directly via --system-extension-image flags
  factory_schematic_request = jsonencode({
    customization = length(var.kernel_args) > 0 ? {
      extraKernelArgs = var.kernel_args
    } : {}
  })
}

# Build custom installer image using Talos imager
resource "null_resource" "build_installer" {
  triggers = {
    talos_version        = var.talos_version
    official_extensions  = join(",", var.official_extensions)
    custom_extensions    = join(",", var.custom_extensions)
    kernel_args          = join(",", var.kernel_args)
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
      echo "Building custom installer ${var.talos_version} with all extensions..."

      # Build installer with all extensions (official + custom)
      # Extensions must be full image references (e.g., ghcr.io/siderolabs/qemu-guest-agent:v1.11.5@sha256:...)
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
