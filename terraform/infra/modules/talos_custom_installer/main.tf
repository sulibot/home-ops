terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

variable "talos_version" {
  type        = string
  description = "Talos version (e.g., v1.11.5)"
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

  # Build the docker run command with all extension flags
  extension_flags = join(" ", [
    for ext in var.custom_extensions :
    "--system-extension-image ${ext}"
  ])
}

# Build custom installer image using Talos imager
resource "null_resource" "build_installer" {
  triggers = {
    talos_version = var.talos_version
    extensions    = join(",", var.custom_extensions)
    registry      = var.output_registry
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Create temp directory for output
      TEMP_DIR=$(mktemp -d)
      trap "rm -rf $TEMP_DIR" EXIT

      echo "Building custom Talos installer ${var.talos_version} with extensions..."

      # Run imager to build custom installer
      docker run --rm \
        -v "$TEMP_DIR:/out" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ghcr.io/siderolabs/imager:${var.talos_version} \
        installer \
        --arch amd64 \
        --platform metal \
        --base-installer-image ghcr.io/siderolabs/installer:${var.talos_version} \
        ${local.extension_flags}

      # Load the built image
      IMAGE_ID=$(docker load < $TEMP_DIR/installer-amd64.tar | grep -oP 'Loaded image ID: sha256:\K.*')

      # Tag and push
      docker tag sha256:$IMAGE_ID ${local.installer_tag}
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
