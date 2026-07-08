# Alias used for SDN/other privileged ops that were created with rootpam
provider "proxmox" {
  alias    = "rootpam"
  endpoint = var.pve_endpoint
  username = var.pve_username   # e.g., root@pam (must have rights)
  password = var.pve_password
  insecure = true
}
