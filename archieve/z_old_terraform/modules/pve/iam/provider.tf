# Token if present; else user/pass (bootstrap)
locals {
  _use_token = var.pve_api_token_id != "" && var.pve_api_token_secret != ""
  _api_token = local._use_token ? "${var.pve_api_token_id}=${var.pve_api_token_secret}" : null
}

provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = local._api_token
  username  = local._use_token ? null : var.pve_username
  password  = local._use_token ? null : var.pve_password
  insecure  = true
}
