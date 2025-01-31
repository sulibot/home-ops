variable "debian_images" {
  default = {
    debian_generic = {
      path      = "https://cloud.debian.org/images/cloud/bookworm-backports/latest/debian-12-backports-generic-amd64.qcow2"
      file_name = "debian-12-backports-generic-amd64.img"
    }
    debian_cloud = {
      path      = "https://cloud.debian.org/images/cloud/bookworm-backports/latest/debian-12-backports-cloud-amd64.qcow2"
      file_name = "debian-12-backports-cloud-amd64.img"
    }
    debian_nocloud = {
      path      = "https://cloud.debian.org/images/cloud/bookworm-backports/latest/debian-12-backports-nocloud-amd64.qcow2"
      file_name = "debian-12-backports-nocloud-amd64.img"
    }
  }
}

variable "ubuntu_images" {
  default = {
    ubuntu_jammy = {
      path     = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
#      checksum = "55c687a9a242fab7b0ec89ac69f9def77696c4e160e6f640879a0b0031a08318"
    }
    ubuntu_noble = {
      path     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
      file_name = "noble-server-cloudimg-amd64.img"
    }
  }
}

# Provision all images using a reusable module
module "proxmox_images" {
  source        = "./modules/proxmox_image"
  images        = merge(var.debian_images, var.ubuntu_images)
  datastore_id  = "resources"
  node_name     = "pve01"
}
