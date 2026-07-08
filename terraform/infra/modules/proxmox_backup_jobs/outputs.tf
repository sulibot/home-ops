output "backup_job_ids" {
  description = "Managed Proxmox backup job IDs."
  value       = keys(proxmox_backup_job.this)
}
