variable "talos_version" {
  description = "Talos version (e.g., v1.11.5)"
  type        = string
}

variable "region" {
  description = "Region identifier (injected by root terragrunt)"
  type        = string
  default     = "home-lab"
}
