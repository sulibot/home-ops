# === Proxmox IAM bootstrap (role + user + token) ===

resource "proxmox_virtual_environment_role" "terraform" {
  role_id    = var.terraform_role_id
  privileges = [
    "Datastore.Allocate","Datastore.AllocateSpace","Datastore.AllocateTemplate","Datastore.Audit",
    "Pool.Allocate","Sys.Audit","Sys.Modify","SDN.Use","User.Modify",
    "VM.Allocate","VM.Audit","VM.Clone",
    "VM.Config.CDROM","VM.Config.Cloudinit","VM.Config.CPU","VM.Config.Disk","VM.Config.HWType",
    "VM.Config.Memory","VM.Config.Network","VM.Config.Options",
    "VM.Migrate","VM.PowerMgmt","Sys.Modify","SDN.Allocate"
  ]
}

resource "proxmox_virtual_environment_user" "terraform" {
  user_id = var.terraform_user_id     # "terraform@pve"
  comment = "Terraform automation user"
  enabled = true

  # Grant our custom role at the datacenter root
  acl {
    path      = var.terraform_acl_path  # "/"
    role_id   = proxmox_virtual_environment_role.terraform.role_id
    propagate = true
  }
}

resource "proxmox_virtual_environment_user_token" "terraform_token" {
  user_id               = proxmox_virtual_environment_user.terraform.user_id
  token_name            = var.terraform_token_name   # "provider" --> token id = terraform@pve!provider
  comment               = "API token for Terraform provider usage"
  privileges_separation = false   # inherit user role ACLs

  depends_on = [proxmox_virtual_environment_user.terraform]
}

# Extract secret part after '=' from the generated token value
locals {
  _tok_value   = proxmox_virtual_environment_user_token.terraform_token.value         # (sensitive) like "terraform@pve!provider=SECRET"
  _tok_parts   = split("=", local._tok_value)
  _tok_secret  = element(local._tok_parts, length(local._tok_parts)-1)
  _tok_id      = proxmox_virtual_environment_user_token.terraform_token.id            # "terraform@pve!provider"
}
