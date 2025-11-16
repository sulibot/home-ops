# outputs.tf)

# Raw 
output "images_raw" {
  value = proxmox_virtual_environment_file.images
}

# Readable summary keyed by your image map keys
output "images_readable" {
  description = "Tidy map keyed by image name with common attributes."
  value = {
    for name, r in proxmox_virtual_environment_file.images :
    name => {
      id          = r.id
      node_name   = r.node_name
      datastore   = r.datastore_id
      content     = r.content_type
      # source_file is a single block; index [0] is safe
      file_name   = try(r.source_file[0].file_name, null)
      source_path = try(r.source_file[0].path, null)
      checksum    = try(r.source_file[0].checksum, null)
      size_bytes  = try(r.size, null)         # exposed by provider on some versions
      created_at  = try(r.creation_date, null) # if available
    }
  }
}