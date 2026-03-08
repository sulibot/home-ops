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

variable "cnpg_restore_rbd_gate_timeout_seconds" {
  description = "Timeout waiting for rbd.csi.ceph.com registration on workers."
  type        = number
  default     = 300
}

variable "cnpg_restore_rbd_self_heal_retries" {
  description = "How many times to restart ceph-csi rbd nodeplugin pods on missing-driver nodes before failing."
  type        = number
  default     = 1
}

variable "cnpg_restore_rbd_self_heal_settle_seconds" {
  description = "Seconds to wait after restarting rbd nodeplugin pods before re-checking CSINode driver registration."
  type        = number
  default     = 20
}

variable "cnpg_restore_rbd_nodeplugin_namespace" {
  description = "Namespace containing the ceph-csi rbd nodeplugin DaemonSet."
  type        = string
  default     = "ceph-csi"
}

variable "cnpg_restore_rbd_nodeplugin_daemonset_name" {
  description = "DaemonSet name for ceph-csi rbd nodeplugin."
  type        = string
  default     = "ceph-csi-rbd-nodeplugin"
}

variable "cnpg_restore_cluster_healthy_timeout_seconds" {
  description = "Timeout waiting for restored CNPG cluster to become healthy."
  type        = number
  default     = 1200
}

variable "cnpg_restore_database_cr_timeout_seconds" {
  description = "Timeout waiting for database CRs to reach applied=true."
  type        = number
  default     = 600
}

variable "cnpg_expected_databases" {
  description = "Database CR names that must exist and report status.applied=true after restore."
  type        = list(string)
  default     = ["atuin", "authentik", "firefly", "paperless"]
}

variable "cnpg_restore_progress_stall_timeout_seconds" {
  description = "Fail if restore makes no observable progress for this many seconds."
  type        = number
  default     = 300
}

variable "cnpg_object_store_probe_mode" {
  description = "Direct object-store preflight mode for barman restore path: off, auto, required."
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["off", "auto", "required"], var.cnpg_object_store_probe_mode)
    error_message = "cnpg_object_store_probe_mode must be off, auto, or required."
  }
}

variable "cnpg_object_store_probe_timeout_seconds" {
  description = "Timeout for direct object-store probe when enabled."
  type        = number
  default     = 120
}

variable "cnpg_restore_flux_kustomization_timeout_seconds" {
  description = "Timeout waiting for CNPG Flux kustomizations to report Ready."
  type        = number
  default     = 600
}

variable "cnpg_restore_flux_kustomization_namespace" {
  description = "Namespace of the CNPG Flux kustomizations."
  type        = string
  default     = "flux-system"
}

variable "cnpg_restore_flux_kustomization_name" {
  description = "Flux kustomization name that applies postgres-vectorchord resources."
  type        = string
  default     = "postgres-vectorchord"
}

variable "cnpg_restore_flux_precheck_kustomization_name" {
  description = "Flux kustomization name for postgres-vectorchord recovery precheck."
  type        = string
  default     = "postgres-vectorchord-recovery-precheck"
}
