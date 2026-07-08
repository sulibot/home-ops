terraform {
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.98.0, < 1.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3.0"
    }
  }
}

resource "proxmox_virtual_environment_role" "this" {
  role_id    = var.role_id
  privileges = var.role_privileges
}

resource "proxmox_virtual_environment_user" "this" {
  user_id = var.user_id
  comment = var.user_comment
  enabled = var.user_enabled
  email   = var.user_email
}

resource "proxmox_acl" "root" {
  path      = var.acl_path
  role_id   = proxmox_virtual_environment_role.this.role_id
  user_id   = proxmox_virtual_environment_user.this.user_id
  propagate = var.acl_propagate
}

resource "proxmox_user_token" "provider" {
  user_id               = proxmox_virtual_environment_user.this.user_id
  token_name            = var.token_name
  comment               = var.token_comment
  privileges_separation = var.token_privileges_separation
}
