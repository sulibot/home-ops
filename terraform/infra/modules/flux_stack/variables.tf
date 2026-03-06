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

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "home-lab"
}
