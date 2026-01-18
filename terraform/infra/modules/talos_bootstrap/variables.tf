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

variable "control_plane_nodes" {
  description = "Control plane node IP addresses from talos_config module"
  type = map(object({
    ipv6 = string
    ipv4 = string
  }))
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint (e.g., https://[fd00:101::10]:6443)"
  type        = string
  default     = ""
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

# Note: Flux-related variables removed - Flux is now deployed via flux-operator and flux-instance modules

variable "repo_root" {
  description = "Repository root path for resolving relative paths in scripts"
  type        = string
  default     = ""
}
