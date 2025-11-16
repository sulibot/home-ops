# Token id is like "terraform@pve!provider"
output "terraform_api_token_id" {
  value = proxmox_virtual_environment_user_token.terraform_token.id
}

# Secret part after "="; mark as sensitive
output "terraform_api_token_secret" {
  value     = local._tok_secret
  sensitive = true
}
