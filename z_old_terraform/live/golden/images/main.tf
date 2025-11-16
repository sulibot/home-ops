

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

output "images" {
  value = proxmox_virtual_environment_file.images
}