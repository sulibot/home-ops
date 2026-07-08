output "directory_storage_ids" {
  description = "Managed directory storage IDs."
  value       = keys(proxmox_storage_directory.directory)
}

output "zfspool_storage_ids" {
  description = "Managed ZFS pool storage IDs."
  value       = keys(proxmox_storage_zfspool.zfspool)
}
