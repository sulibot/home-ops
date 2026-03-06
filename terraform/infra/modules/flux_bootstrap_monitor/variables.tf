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
