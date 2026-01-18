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
