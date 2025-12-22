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

variable "kernel_args" {
  type        = list(string)
  description = "Extra kernel arguments to include in the ISO"
  default     = []
}

variable "output_dir" {
  type        = string
  description = "Directory to output the generated ISO file"
}

variable "iso_name" {
  type        = string
  description = "Name of the ISO file to generate"
}

locals {
  iso_path = "${var.output_dir}/${var.iso_name}"

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

# Build custom nocloud boot ISO using Talos imager
resource "null_resource" "build_boot_iso" {
  triggers = {
    talos_version       = var.talos_version
    official_extensions = join(",", var.official_extensions)
    custom_extensions   = join(",", var.custom_extensions)
    kernel_args         = join(",", var.kernel_args)
    output_path         = local.iso_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Getting factory schematic ID for official extensions..."

      # Get factory schematic ID for official extensions
      SCHEMATIC_ID=$(curl -s "https://factory.talos.dev/schematics" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '${local.factory_schematic_request}' | \
        jq -r '.id')

      echo "Factory schematic ID: $SCHEMATIC_ID"
      echo "Building custom nocloud boot ISO ${var.talos_version} with all extensions..."

      # Create output directory
      mkdir -p ${var.output_dir}

      # Build nocloud ISO with all extensions (official + custom)
      # Extensions must be full image references (e.g., ghcr.io/siderolabs/qemu-guest-agent:v1.11.5@sha256:...)
      docker run --rm \
        -v "${var.output_dir}:/out" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ghcr.io/siderolabs/imager:${var.talos_version} \
        iso \
        --arch amd64 \
        --tar-to-stdout=false \
        --output-kind iso \
        ${local.extension_flags}

      # Rename the output file to our desired name
      mv "${var.output_dir}/metal-amd64.iso" "${local.iso_path}"

      echo "Custom boot ISO generated at ${local.iso_path}"
    EOT
  }
}

output "iso_path" {
  value       = local.iso_path
  description = "Path to the generated boot ISO file"
  depends_on  = [null_resource.build_boot_iso]
}

output "iso_name" {
  value       = var.iso_name
  description = "Name of the generated ISO file"
}

output "talos_version" {
  value       = var.talos_version
  description = "Talos version of the boot ISO"
}
