include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "${get_repo_root()}/terraform/modules/pve/cluster-services"
}

locals {
  globals = read_terragrunt_config(find_in_parent_folders("common/globals.hcl")).locals
  secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/live/common/secrets.sops.yaml"))
}

inputs = {
  # --- Proxmox auth (bootstrap with user/pass; leave token empty) ---
  pve_endpoint         = local.secrets.pve_endpoint
  pve_api_token_id     = ""
  pve_api_token_secret = ""
  pve_username         = local.secrets.pve_username
  pve_password         = local.secrets.pve_password

  # --- ACME + DNS ---
  acme_account_name  = "default"
  acme_contact_email = local.secrets.acme_contact_email
  acme_directory     = "production" # or "staging" for testing

  dns_plugin = {
    id  = "cloudflare"
    api = "cf"           # not "dns_cf"
    data = {
      CF_Token      = local.secrets.cloudflare_api_token
      CF_Account_ID = local.secrets.cloudflare_account_id
    }
    validation_delay = 30
  }


  nodes = [
    { ssh_host = "root@pve01", domains = ["pve01.sulibot.com"] },
    # { ssh_host = "root@pve02", domains = ["pve02.sulibot.com"] },
    # { ssh_host = "root@pve03", domains = ["pve03.sulibot.com","alt.sulibot.com"] },
  ]

  order_on_apply = true
}
