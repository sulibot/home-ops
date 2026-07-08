variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "nodes" {
  description = "Node API-level metadata keyed by Proxmox node name."
  type = map(object({
    description = optional(string)
  }))
  default = {}
}
