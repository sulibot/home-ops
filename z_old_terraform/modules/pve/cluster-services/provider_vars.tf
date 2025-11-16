# --- Proxmox provider inputs (support both bootstrap with user/pass and steady-state with token)

variable "pve_endpoint" {
  type = string
}

variable "pve_api_token_id" {
  type      = string
  default   = ""       # empty means: not using token
  sensitive = true
}

variable "pve_api_token_secret" {
  type      = string
  default   = ""       # empty means: not using token
  sensitive = true
}

variable "pve_username" {
  type    = string
  default = ""         # empty means: using token
}

variable "pve_password" {
  type      = string
  default   = ""       # empty means: using token
  sensitive = true
}
