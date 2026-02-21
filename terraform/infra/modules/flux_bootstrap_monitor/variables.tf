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

variable "auto_switch_intervals" {
  description = "Automatically delete the bootstrap override ConfigMap after bootstrap completes, reverting apps to their individual production defaults"
  type        = bool
  default     = true
}

# Bootstrap override values written to the cluster-settings ConfigMap immediately.
# These temporarily override each app's ${VAR:=production_default} with aggressive
# bootstrap intervals. After bootstrap, the ConfigMap is deleted and apps revert
# to their own defaults defined in each ks.yaml file.

variable "tier0_bootstrap_interval" {
  description = "Tier 0 reconciliation interval during bootstrap (override)"
  type        = string
  default     = "30s"
}

variable "tier0_bootstrap_retry_interval" {
  description = "Tier 0 retry interval during bootstrap (override)"
  type        = string
  default     = "10s"
}

variable "tier1_bootstrap_interval" {
  description = "Tier 1 reconciliation interval during bootstrap (override)"
  type        = string
  default     = "1m"
}

variable "tier1_bootstrap_retry_interval" {
  description = "Tier 1 retry interval during bootstrap (override)"
  type        = string
  default     = "20s"
}

variable "tier2_bootstrap_interval" {
  description = "Tier 2 reconciliation interval during bootstrap (override)"
  type        = string
  default     = "2m"
}

variable "tier2_bootstrap_retry_interval" {
  description = "Tier 2 retry interval during bootstrap (override)"
  type        = string
  default     = "30s"
}
