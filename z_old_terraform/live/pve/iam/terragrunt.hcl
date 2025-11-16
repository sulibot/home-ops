# live/pve/iam/terragrunt.hcl
include "root" { path = find_in_parent_folders("root.hcl") }

terraform {
  source = "${get_repo_root()}/terraform/modules/pve/iam"
}

locals {
  # Decrypt secrets; if file is missing/empty/invalid, fall back to {}
  _raw_secrets = try(
    yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/live/common/secrets.sops.yaml")),
    {}
  )
  secrets = local._raw_secrets == null ? {} : local._raw_secrets
}

inputs = {
  # --- Proxmox auth (bootstrap with user/pass; leave token empty) ---
  pve_endpoint         = lookup(local.secrets, "pve_endpoint", "")
  pve_username         = lookup(local.secrets, "pve_username", "")
  pve_password         = lookup(local.secrets, "pve_password", "")
  pve_api_token_id     = ""
  pve_api_token_secret = ""

  # --- Where to write the generated token (SOPS in-place update) ---
  sops_file_path = "${get_repo_root()}/terraform/live/common/secrets.sops.yaml"
  # write_token_to_sops = true  # optional; defaults to true in your module
}
