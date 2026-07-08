# --- Proxmox API auth (bootstrap with user/pass; later you may use token) ---
variable "pve_endpoint"           { type = string }
variable "pve_api_token_id"       { 
    type = string
    sensitive = true
    default = "" 
    }
variable "pve_api_token_secret"   { 
    type = string
    sensitive = true
    default = "" 
    }
variable "pve_username"           { 
    type = string
    default = "" 
    }
variable "pve_password"           { 
    type = string
    sensitive = true
    default = "" 
    }

# --- Where to write the generated token (encrypted in-place with SOPS) ---
variable "sops_file_path"         { type = string }

# Control whether we patch SOPS (useful for dry-runs/tests)
variable "write_token_to_sops"    { 
    type = bool
    default = true 
    }

# --- IAM naming (override if you want) ---
variable "terraform_user_id"      { 
    type = string
    default = "terraform@pve" 
    }
variable "terraform_role_id"      { 
    type = string
    default = "Terraform" 
    }
variable "terraform_token_name"   { 
    type = string
    default = "provider" 
    } # => token id: terraform@pve!provider
variable "terraform_acl_path"     { 
    type = string
    default = "/" 
    }
# --- SDN EVPN controller (the missing piece) ---
#variable "sdn_controller" {
#  type = object({
#    id     = string          # e.g., "evpn-ctrl"
#    asn    = number          # e.g., 65001
#    peers  = list(string)    # e.g., ["192.0.2.1","192.0.2.2"]; may be empty
#    fabric = optional(string) # e.g., "mesh" (defaults to mesh if omitted)
#  })
#}

# SSH options for the Proxmox provider (used for uploads/exec helpers)
variable "pve_ssh_user" {
  type        = string
  description = "SSH username for Proxmox nodes (defaults to root if null)."
  default     = null
}

variable "pve_ssh_agent" {
  type        = bool
  description = "Use ssh-agent for auth."
  default     = true
}

variable "pve_ssh_private_key" {
  type        = string
  description = "PEM contents of a private key. Leave null to rely on ssh-agent."
  sensitive   = true
  default     = null
}
