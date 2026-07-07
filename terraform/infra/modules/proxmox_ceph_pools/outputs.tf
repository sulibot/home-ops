output "managed_pool_ids" {
  description = "Pool resource IDs currently managed by Terraform."
  value       = { for name, pool in proxmox_ceph_pool.this : name => pool.id }
}

output "cataloged_pool_names" {
  description = "All pool names present in the input catalog, including unmanaged pools."
  value       = keys(var.ceph_pools)
}
