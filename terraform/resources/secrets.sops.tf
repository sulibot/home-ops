data "sops_file" "auth-secrets" {
    source_file = "secrets.sops.yaml"
}

# Output decrypted data for debugging purposes
#output "decrypted_data" {
#  value = data.sops_file.auth-secrets.data
#}

# Expose decrypted values as local variables
locals {
  pve_endpoint          = data.sops_file.auth-secrets.data["pve_endpoint"]
  pve_api_token_id      = data.sops_file.auth-secrets.data["pve_api_token_id"]
  pve_api_token_secret  = data.sops_file.auth-secrets.data["pve_api_token_secret"]
  pve_username          = data.sops_file.auth-secrets.data["pve_username"]
  pve_password          = data.sops_file.auth-secrets.data["pve_password"]
}


#    sops = {
#      source  = "carlpett/sops"
#      version = "1.1.1"
#    }