variable "flux_operator_version" {
  description = "Version of flux-operator Helm chart"
  type        = string
  default     = "0.14.0"
}

variable "flux_version" {
  description = "Version of Flux to deploy"
  type        = string
  default     = "2.4.0"
}

variable "git_repository" {
  description = "Git repository URL for Flux sync"
  type        = string
}

variable "git_branch" {
  description = "Git branch for Flux sync"
  type        = string
  default     = "main"
}

variable "git_path" {
  description = "Path in Git repository for Flux sync"
  type        = string
}

variable "sops_age_key" {
  description = "SOPS AGE private key for decrypting secrets"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
}

variable "kubeconfig_content" {
  description = "Kubeconfig content for Kubernetes provider"
  type        = string
  sensitive   = true
}

variable "kubernetes_api_host" {
  description = "Optional explicit Kubernetes API host override for flux-operator bootstrap"
  type        = string
  default     = ""
}

variable "github_token" {
  description = "GitHub token for Git authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "repo_root" {
  description = "Repository root path for post-bootstrap scripts"
  type        = string
  default     = ""
}

variable "bootstrap_mode" {
  description = "Run bootstrap-time monitor and recovery orchestration. Keep false for steady-state applies."
  type        = bool
  default     = false
}

variable "bootstrap_timeout_seconds" {
  description = "Timeout for bootstrap capability-gate checks."
  type        = number
  default     = 300
}

variable "cnpg_new_db" {
  description = "Allow fresh DB bootstrap when no CNPG backup exists. Default false (restore-required mode)."
  type        = bool
  default     = false
}

variable "cnpg_restore_mode" {
  description = "CNPG restore policy mode: RESTORE_REQUIRED or NEW_DB."
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

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "home-lab"
}
