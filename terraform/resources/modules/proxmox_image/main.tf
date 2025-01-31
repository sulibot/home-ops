variable "images" {
  description = "Map of images with paths, file names, and optional checksums"
}

variable "datastore_id" {
  description = "Proxmox datastore to store the images"
}

variable "node_name" {
  description = "The Proxmox node where the images will be stored"
}

resource "proxmox_virtual_environment_file" "images" {
  for_each     = var.images
  content_type = "iso"
  datastore_id = var.datastore_id
  node_name    = var.node_name

  source_file {
    path      = each.value.path
    file_name = lookup(each.value, "file_name", null)
    checksum  = lookup(each.value, "checksum", null)
  }
}
