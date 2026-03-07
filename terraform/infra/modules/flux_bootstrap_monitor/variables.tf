# Passed globally by root.hcl extra_arguments to all modules; unused here
variable "region" {
  description = "Deployment region (passed globally by root terragrunt config)"
  type        = string
  default     = "home-lab"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
}

variable "bootstrap_timeout_seconds" {
  description = "Timeout for capability-gate bootstrap checks."
  type        = number
  default     = 300
}

variable "cnpg_new_db" {
  description = "Allow fresh DB bootstrap when no CNPG backup is found. Default false (restore-required)."
  type        = bool
  default     = false
}

variable "cnpg_restore_mode" {
  description = "CNPG restore policy mode: RESTORE_REQUIRED or NEW_DB. Overrides cnpg_new_db when set explicitly."
  type        = string
  default     = "RESTORE_REQUIRED"

  validation {
    condition     = contains(["RESTORE_REQUIRED", "NEW_DB"], var.cnpg_restore_mode)
    error_message = "cnpg_restore_mode must be RESTORE_REQUIRED or NEW_DB."
  }
}

variable "cnpg_restore_method" {
  description = "CNPG restore source preference: auto, barman, or snapshot."
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "barman", "snapshot"], var.cnpg_restore_method)
    error_message = "cnpg_restore_method must be auto, barman, or snapshot."
  }
}

variable "cnpg_backup_max_age_hours" {
  description = "Maximum acceptable backup age for restore-required mode."
  type        = number
  default     = 36

  validation {
    condition     = var.cnpg_backup_max_age_hours > 0
    error_message = "cnpg_backup_max_age_hours must be greater than 0."
  }
}

variable "cnpg_stale_backup_max_age_minutes" {
  description = "Delete non-completed backup CRs older than this during restore orchestration."
  type        = number
  default     = 45

  validation {
    condition     = var.cnpg_stale_backup_max_age_minutes > 0
    error_message = "cnpg_stale_backup_max_age_minutes must be greater than 0."
  }
}

variable "cnpg_storage_size" {
  description = "CNPG storage size to enforce during restore cluster re-creation."
  type        = string
  default     = "60Gi"
}
