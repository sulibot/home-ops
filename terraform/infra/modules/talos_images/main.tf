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
  description = "Region identifier (not used by this module, but required by root.hcl)"
  default     = ""
}

variable "talos_version" {
  type        = string
  description = "Talos version (e.g., v1.11.5)"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version (e.g., 1.31.4)"
}

variable "official_extensions" {
  type        = list(string)
  description = "List of official system extension images with digests"
  default     = []
}

variable "custom_extensions" {
  type        = list(string)
  description = "List of custom system extension images"
  default     = []
}

variable "kernel_args" {
  type        = list(string)
  description = "Extra kernel arguments"
  default     = []
}

variable "installer_registry" {
  type        = string
  description = "Container registry for installer image (e.g., ghcr.io/username/repo)"
}

variable "iso_output_dir" {
  type        = string
  description = "Directory to output the boot ISO"
}

variable "iso_name" {
  type        = string
  description = "Name for the boot ISO file"
}

variable "proxmox_datastore_id" {
  type        = string
  description = "Proxmox datastore to upload ISO to"
  default     = ""
}

variable "proxmox_node_names" {
  type        = list(string)
  description = "List of Proxmox node names (only first node used for Ceph upload)"
  default     = []
}

variable "proxmox_node_hostnames" {
  type        = list(string)
  description = "List of Proxmox node hostnames for SSH access (only first used for Ceph)"
  default     = []
}

variable "upload_to_proxmox" {
  type        = bool
  description = "Whether to upload ISO to Proxmox after building"
  default     = true
}

locals {
  installer_tag = "${var.installer_registry}:${var.talos_version}"

  # Build extension flags for ALL extensions (official + custom)
  extension_flags = join(" ", [
    for ext in concat(var.official_extensions, var.custom_extensions) :
    "--system-extension-image ${ext}"
  ])

  # Factory schematic for kernel args only (extensions added via flags)
  factory_schematic_request = jsonencode({
    customization = length(var.kernel_args) > 0 ? {
      extraKernelArgs = var.kernel_args
    } : {}
  })
}

# Build both installer and ISO in a single step
# They share the same extensions and configuration
resource "null_resource" "build_images" {
  triggers = {
    talos_version        = var.talos_version
    official_extensions  = join(",", var.official_extensions)
    custom_extensions    = join(",", var.custom_extensions)
    kernel_args          = join(",", var.kernel_args)
    installer_registry   = var.installer_registry
    iso_output_dir       = var.iso_output_dir
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "=================================================="
      echo "Building Talos ${var.talos_version} Images"
      echo "Installer: ${local.installer_tag}"
      echo "ISO: ${var.iso_output_dir}/${var.iso_name}"
      echo "=================================================="

      # Get factory schematic ID for kernel args
      SCHEMATIC_ID=$(curl -s "https://factory.talos.dev/schematics" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '${local.factory_schematic_request}' | \
        jq -r '.id')

      echo "Factory schematic ID: $SCHEMATIC_ID"

      # ============================================================
      # STEP 1: Build Installer Image (metal platform)
      # ============================================================
      echo ""
      echo "Building installer image (platform: metal)..."

      TEMP_DIR=$(mktemp -d)
      trap "rm -rf $TEMP_DIR" EXIT

      docker run --rm \
        -v "$TEMP_DIR:/out" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ghcr.io/siderolabs/imager:${var.talos_version} \
        installer \
        --arch amd64 \
        --platform metal \
        --base-installer-image factory.talos.dev/installer/$SCHEMATIC_ID:${var.talos_version} \
        ${local.extension_flags}

      # Load, tag, and push installer to registry
      LOADED_IMAGE=$(docker load < $TEMP_DIR/installer-amd64.tar | sed -n 's/^Loaded image: //p')
      docker tag "$LOADED_IMAGE" ${local.installer_tag}

      echo "Pushing installer to registry..."
      docker push ${local.installer_tag}

      echo "✓ Installer image built, tagged, and pushed as ${local.installer_tag}"

      # ============================================================
      # STEP 2: Build Boot ISO (nocloud platform)
      # ============================================================
      echo ""
      echo "Building boot ISO (platform: nocloud for cloud-init)..."

      mkdir -p ${var.iso_output_dir}

      docker run --rm \
        -v "${var.iso_output_dir}:/out" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        ghcr.io/siderolabs/imager:${var.talos_version} \
        iso \
        --arch amd64 \
        --platform nocloud \
        --base-installer-image factory.talos.dev/installer/$SCHEMATIC_ID:${var.talos_version} \
        --tar-to-stdout=false \
        --output-kind iso \
        ${local.extension_flags}

      # Rename output to desired name (imager outputs nocloud-amd64.iso)
      mv "${var.iso_output_dir}/nocloud-amd64.iso" "${var.iso_output_dir}/${var.iso_name}"

      echo "✓ Boot ISO created at ${var.iso_output_dir}/${var.iso_name}"

      echo ""
      echo "=================================================="
      echo "Build Complete"
      echo "=================================================="
    EOT
  }
}

output "installer_image" {
  value       = local.installer_tag
  description = "Custom installer image reference"
  depends_on  = [null_resource.build_images]
}

output "iso_path" {
  value       = "${var.iso_output_dir}/${var.iso_name}"
  description = "Path to the boot ISO file"
  depends_on  = [null_resource.build_images]
}

output "iso_name" {
  value       = var.iso_name
  description = "Name of the boot ISO file"
}

output "talos_version" {
  value       = var.talos_version
  description = "Talos version"
}

output "kubernetes_version" {
  value       = var.kubernetes_version
  description = "Kubernetes version"
}
