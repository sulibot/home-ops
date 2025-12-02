variable "cluster_id" {
  description = "Cluster ID for config file paths"
  type        = string
}

variable "talosconfig" {
  description = "Talosconfig YAML string (for CLI/export only)"
  type        = string
  sensitive   = true
}

variable "client_configuration" {
  description = "Talos client configuration object from talos_machine_secrets"
  type        = any
  sensitive   = true
}

variable "machine_configs" {
  description = "Machine configurations from talos_config module"
  type = map(object({
    machine_type          = string
    machine_configuration = string
    config_patch          = string
  }))
  sensitive = true
}

variable "all_node_names" {
  description = "List of all node names (non-sensitive)"
  type        = list(string)
}

variable "all_node_ips" {
  description = "All node IP addresses from talos_config module"
  type = map(object({
    ipv6 = string
    ipv4 = string
  }))
}

variable "control_plane_nodes" {
  description = "Control plane node IP addresses from talos_config module"
  type = map(object({
    ipv6 = string
    ipv4 = string
  }))
}

variable "region" {
  description = "Region identifier"
  type        = string
  default     = "home-lab"
}

variable "cilium_values" {
  description = "Additional Cilium Helm values to merge with defaults"
  type        = any
  default     = {}
}

variable "flux_git_repository" {
  description = "Git repository URL for Flux bootstrap (empty to skip Flux)"
  type        = string
  default     = ""
}

variable "flux_git_branch" {
  description = "Git branch for Flux bootstrap"
  type        = string
  default     = "main"
}

variable "flux_github_token" {
  description = "GitHub Personal Access Token for Flux Git authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "sops_age_key" {
  description = "SOPS AGE private key for decrypting secrets (read from SOPS_AGE_KEY_FILE env var, empty to skip)"
  type        = string
  sensitive   = true
  default     = ""
}
