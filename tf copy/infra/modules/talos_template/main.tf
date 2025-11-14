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

variable "proxmox_node" {
  type        = string
  description = "Proxmox node to create template on"
}

variable "template_vmid" {
  type        = number
  description = "VM ID for the template"
}

variable "template_name" {
  type        = string
  description = "Name for the template VM"
}

variable "talos_image_path" {
  type        = string
  description = "Local path to the Talos image file"
}

variable "disk_storage" {
  type        = string
  description = "Storage for the VM disk (e.g., rbd-vm)"
  default     = "rbd-vm"
}

variable "disk_size" {
  type        = string
  description = "Disk size (e.g., 60G)"
  default     = "60G"
}

locals {
  # Check if image file exists
  image_exists = fileexists(var.talos_image_path)
}

# Create template VM via SSH
resource "null_resource" "create_template" {
  triggers = {
    image_path    = var.talos_image_path
    template_vmid = var.template_vmid
    template_name = var.template_name
    disk_storage  = var.disk_storage
  }

  # Upload image to Proxmox node
  provisioner "local-exec" {
    command = <<-EOT
      scp -o StrictHostKeyChecking=no "${var.talos_image_path}" root@${var.proxmox_node}:/tmp/${basename(var.talos_image_path)}
    EOT
  }

  # Create VM and import disk
  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no root@${var.proxmox_node} <<'ENDSSH'
        # Remove existing VM/template if it exists
        if qm status ${var.template_vmid} >/dev/null 2>&1; then
          qm destroy ${var.template_vmid} || true
        fi

        # Create VM
        qm create ${var.template_vmid} \
          --name "${var.template_name}" \
          --memory 2048 \
          --cores 2 \
          --net0 virtio,bridge=vmbr0 \
          --scsihw virtio-scsi-pci \
          --machine q35 \
          --bios seabios

        # Import disk
        qm importdisk ${var.template_vmid} /tmp/${basename(var.talos_image_path)} ${var.disk_storage} --format raw

        # Attach disk
        qm set ${var.template_vmid} --scsi0 ${var.disk_storage}:vm-${var.template_vmid}-disk-1

        # Resize disk
        qm resize ${var.template_vmid} scsi0 ${var.disk_size}

        # Set boot order
        qm set ${var.template_vmid} --boot order=scsi0

        # Convert to template
        qm template ${var.template_vmid}

        # Cleanup temp file
        rm -f /tmp/${basename(var.talos_image_path)}
      ENDSSH
    EOT
  }

  # Destroy provisioner
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no root@${self.triggers.template_name} "qm destroy ${self.triggers.template_vmid} || true" || true
    EOT
  }
}

output "template_vmid" {
  value       = var.template_vmid
  description = "The VM ID of the created template"
}

output "template_name" {
  value       = var.template_name
  description = "The name of the created template"
}
