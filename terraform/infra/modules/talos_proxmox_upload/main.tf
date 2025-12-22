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

variable "iso_path" {
  type        = string
  description = "Local path to the ISO file to upload"
}

variable "iso_name" {
  type        = string
  description = "Name of the ISO file"
}

variable "talos_version" {
  type        = string
  description = "Talos version"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
}

variable "proxmox_datastore_id" {
  type        = string
  description = "Proxmox datastore to upload ISO to"
}

variable "proxmox_node_names" {
  type        = list(string)
  description = "List of Proxmox node names (only first node used for Ceph upload)"
}

variable "proxmox_node_hostnames" {
  type        = list(string)
  description = "List of Proxmox node hostnames for SSH access (only first used for Ceph)"
}

# Upload the ISO file to first Proxmox node using SCP
# Since resources datastore is Ceph-backed, uploading to one node makes it available to all
# The proxmox provider's download_file resource only supports URLs, not local files
# So we use null_resource with SCP to copy the local ISO to Proxmox
resource "null_resource" "upload_iso" {
  triggers = {
    iso_path     = var.iso_path
    iso_name     = var.iso_name
    datastore_id = var.proxmox_datastore_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      # Upload to first node only (Ceph storage is shared across all nodes)
      NODE_HOSTNAME="${var.proxmox_node_hostnames[0]}"
      NODE_NAME="${var.proxmox_node_names[0]}"
      DEST_DIR="/mnt/pve/${var.proxmox_datastore_id}/template/iso"
      DEST_FILE="$DEST_DIR/${var.iso_name}"

      echo "Uploading ${var.iso_name} to $NODE_HOSTNAME ($NODE_NAME) on Ceph storage..."

      # Create the directory if it doesn't exist
      ssh root@$NODE_HOSTNAME "mkdir -p $DEST_DIR"

      # Copy the ISO (always upload to ensure latest version)
      scp "${var.iso_path}" root@$NODE_HOSTNAME:$DEST_FILE

      # Set proper permissions
      ssh root@$NODE_HOSTNAME "chmod 644 $DEST_FILE"

      echo "Upload complete - ISO available on all Proxmox nodes via Ceph"
    EOT
  }
}

output "talos_image_file_ids" {
  value = {
    for node_name in var.proxmox_node_names :
    node_name => "${var.proxmox_datastore_id}:iso/${var.iso_name}"
  }
  description = "Map of node names to uploaded Talos image file IDs"
  depends_on  = [null_resource.upload_iso]
}

output "talos_image_file_name" {
  value       = var.iso_name
  description = "Name of the uploaded Talos image file"
}

output "talos_image_id" {
  value       = "local-build-${var.talos_version}"
  description = "Identifier for the Talos image (for compatibility)"
}

output "talos_version" {
  value       = var.talos_version
  description = "Talos version"
}

output "kubernetes_version" {
  value       = var.kubernetes_version
  description = "Kubernetes version"
}
