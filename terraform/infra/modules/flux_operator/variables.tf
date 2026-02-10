variable "flux_operator_version" {
  description = "Version of flux-operator Helm chart"
  type        = string
  default     = "0.14.0"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file for kubectl commands"
  type        = string
}

variable "kubeconfig_content" {
  description = "Kubeconfig content for Helm provider"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region identifier (passed by Terragrunt, not used by this module)"
  type        = string
  default     = ""
}

variable "wait_for_cilium" {
  description = "Wait for Cilium CNI to be ready before deploying flux-operator (prevents crashloop)"
  type        = bool
  default     = true
}

variable "cilium_wait_timeout" {
  description = "Maximum time to wait for Cilium to be ready (seconds)"
  type        = number
  default     = 300
}

variable "startup_probe_failure_threshold" {
  description = "Startup probe failure threshold for flux-operator (prevents restart loops)"
  type        = number
  default     = 60
}
