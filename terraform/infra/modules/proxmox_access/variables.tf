variable "region" {
  description = "Deployment region label passed by the shared Terragrunt root configuration."
  type        = string
}

variable "role_id" {
  description = "Proxmox role to manage for Terraform automation."
  type        = string
}

variable "role_privileges" {
  description = "Privileges granted to the Terraform automation role."
  type        = list(string)
}

variable "user_id" {
  description = "Proxmox user to manage for Terraform automation."
  type        = string
}

variable "user_comment" {
  description = "Comment attached to the Terraform automation user."
  type        = string
  default     = "Terraform automation user"
}

variable "user_email" {
  description = "Email address attached to the Terraform automation user."
  type        = string
  default     = ""
}

variable "user_enabled" {
  description = "Whether the Terraform automation user is enabled."
  type        = bool
  default     = true
}

variable "acl_path" {
  description = "Proxmox ACL path for the Terraform automation user."
  type        = string
  default     = "/"
}

variable "acl_propagate" {
  description = "Whether the ACL propagates to child paths."
  type        = bool
  default     = true
}

variable "token_name" {
  description = "API token name for provider authentication."
  type        = string
}

variable "token_comment" {
  description = "Comment attached to the API token."
  type        = string
  default     = "API token for Terraform provider usage"
}

variable "token_privileges_separation" {
  description = "Whether token privileges are separated from the parent user."
  type        = bool
  default     = false
}
