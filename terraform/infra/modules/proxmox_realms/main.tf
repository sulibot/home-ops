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

resource "proxmox_realm_openid" "openid" {
  for_each = var.openid_realms

  realm      = each.key
  issuer_url = each.value.issuer_url
  client_id  = each.value.client_id

  acr_values        = try(each.value.acr_values, null)
  audiences         = try(each.value.audiences, null)
  autocreate        = try(each.value.autocreate, null)
  comment           = try(each.value.comment, null)
  default           = try(each.value.default, null)
  groups_autocreate = try(each.value.groups_autocreate, null)
  groups_claim      = try(each.value.groups_claim, null)
  groups_overwrite  = try(each.value.groups_overwrite, null)
  prompt            = try(each.value.prompt, null)
  query_userinfo    = try(each.value.query_userinfo, null)
  scopes            = try(each.value.scopes, null)
  username_claim    = try(each.value.username_claim, null)

  lifecycle {
    ignore_changes = [
      client_key,
      client_key_wo,
      client_key_wo_version,
    ]
  }
}
