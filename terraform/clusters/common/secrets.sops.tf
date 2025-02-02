data "sops_file" "auth-secrets" {
  source_file = "${path.module}/secrets.sops.yaml"
}



locals {
  pve_endpoint          = data.sops_file.auth-secrets.data["pve_endpoint"]
  pve_api_token_id      = data.sops_file.auth-secrets.data["pve_api_token_id"]
  pve_api_token_secret  = data.sops_file.auth-secrets.data["pve_api_token_secret"]
  pve_username          = data.sops_file.auth-secrets.data["pve_username"]
  pve_password          = data.sops_file.auth-secrets.data["pve_password"]
  vm_password          = data.sops_file.auth-secrets.data["vm_password"]
}

