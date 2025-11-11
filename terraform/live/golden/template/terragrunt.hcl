# ===== ./terragrunt.hcl =====
include { path = find_in_parent_folders("root.hcl") }

dependency "images" {
  config_path = "${get_repo_root()}/terraform/live/golden/images"
}

terraform {
  source = "."
}

locals {
  globals = read_terragrunt_config(find_in_parent_folders("common/globals.hcl")).locals
  secrets = yamldecode(sops_decrypt_file("${get_repo_root()}/terraform/live/common/secrets.sops.yaml"))
  #  cluster = read_terragrunt_config(find_in_parent_folders("cluster.tfvars")).inputs
}

inputs = merge(
  local.globals,
  {
    pve_api_token_id     = local.secrets.pve_api_token_id
    pve_api_token_secret = local.secrets.pve_api_token_secret
    pve_endpoint         = local.secrets.pve_endpoint
    pve_username         = local.secrets.pve_username
    pve_password         = local.secrets.pve_password
    vm_password          = local.secrets.vm_password

    node_name    = "pve01" # used by provider ssh.host fallback
    datastore_id = local.globals.snippet_datastore_id

    # Correct image reference: update the key to 'debian_12' or the image you want to use
    template_image_id = dependency.images.outputs.images["debian_13"].id

    # --- NEW: explicit SSH settings for provider's ssh{} block ---
    pve_ssh_user  = "root"
    pve_ssh_host  = "pve01.sulibot.com" # or the management IP you SSH to
    pve_ssh_agent = true
    # pve_ssh_private_key = file("~/.ssh/id_ed25519")  # if not using ssh-agent
  }
)