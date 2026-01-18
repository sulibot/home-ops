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

variable "github_token" {
  description = "GitHub token for Git authentication (if needed)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "repo_root" {
  description = "Repository root path for post-bootstrap scripts"
  type        = string
  default     = ""
}

variable "region" {
  description = "Region identifier (passed by Terragrunt, not used by this module)"
  type        = string
  default     = ""
}
