terraform {
  source = "../../../modules/proxmox_acme"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "versions" {
  path = find_in_parent_folders("common/versions.hcl")
}

include "credentials" {
  path = find_in_parent_folders("common/credentials.hcl")
}

locals {
  credentials  = read_terragrunt_config(find_in_parent_folders("common/credentials.hcl"))
  secrets_file = try(local.credentials.locals.secrets_file, local.credentials.inputs.secrets_file)
  secrets      = yamldecode(sops_decrypt_file(local.secrets_file))
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "sops" {}

data "sops_file" "proxmox" {
  source_file = "${local.secrets_file}"
}

provider "proxmox" {
  endpoint = data.sops_file.proxmox.data["pve_endpoint"]
  username = "root@pam"
  password = data.sops_file.proxmox.data["pve_password"]
  insecure = true
}
EOF
}

inputs = {
  accounts = {
    default = {
      contact   = local.secrets.acme_contact_email
      directory = "https://acme-v02.api.letsencrypt.org/directory"
      tos       = "true"
    }
  }

  dns_plugins = {
    cloudflare = {
      api              = "cf"
      validation_delay = 30
    }
  }
}
