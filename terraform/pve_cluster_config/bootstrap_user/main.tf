# bootstrap_user/main.tf

provider "proxmox" {
  endpoint = local.pve_endpoint
  username = local.pve_username
  password = data.sops_file.bootstrap_secrets.data["pve_terraform_user_password"]
  tmp_dir  = "/var/tmp"

  ssh {
    agent    = true
    username = "root"
  }
}

locals {
  pve_endpoint = "https://pve01.sulibot.com:8006/api2/json"
  pve_username = "root@pam"
}

# Load sensitive values using SOPS
data "sops_file" "bootstrap_secrets" {
  source_file = "bootstrap_user.sops.yaml"
}

# Create the Terraform role with custom privileges
resource "proxmox_virtual_environment_role" "terraform_role" {
  role_id = "Terraform"
  privileges = [
    "Datastore.Allocate",
    "Datastore.AllocateSpace",
    "Datastore.AllocateTemplate",
    "Datastore.Audit",
    "Pool.Allocate",
    "Sys.Audit",
    "Sys.Console",
    "Sys.Modify",
    "SDN.Use",
    "VM.Allocate",
    "VM.Audit",
    "VM.Clone",
    "VM.Config.CDROM",
    "VM.Config.Cloudinit",
    "VM.Config.CPU",
    "VM.Config.Disk",
    "VM.Config.HWType",
    "VM.Config.Memory",
    "VM.Config.Network",
    "VM.Config.Options",
    "VM.Migrate",
    "VM.Monitor",
    "VM.PowerMgmt",
    "User.Modify"
  ]
}

# Create the terraform@pve user
resource "proxmox_virtual_environment_user" "terraform_user" {
  user_id  = "terraform@pve"
  password = data.sops_file.bootstrap_secrets.data["pve_terraform_user_password"]
  enabled  = true
  comment  = "Terraform automation user"
  groups   = []
}

# Create an API token for terraform@pve
resource "proxmox_virtual_environment_user_token" "terraform_token" {
  user_id    = proxmox_virtual_environment_user.terraform_user.id
  token_name = "terraform-token"
  comment    = "Token for Terraform Provider"
  # privileged = true  # Optional if needed
}

# Output the token ID (e.g., terraform@pve!terraform-token)
output "terraform_api_token_id" {
  value = "${proxmox_virtual_environment_user_token.terraform_token.user_id}!${proxmox_virtual_environment_user_token.terraform_token.token_name}"
}

# Output the token secret (sensitive)
# To reveal this value after apply, run:
#   tofu output terraform_api_token_secret
output "terraform_api_token_secret" {
  value     = proxmox_virtual_environment_user_token.terraform_token.value
  sensitive = true
}
