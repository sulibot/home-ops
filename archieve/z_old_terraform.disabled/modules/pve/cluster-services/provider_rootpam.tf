# Alias used only for ACME resources (must be root@pam)
provider "proxmox" {
  alias    = "rootpam"
  endpoint = var.pve_endpoint
  username = var.pve_username   # root@pam
  password = var.pve_password
  insecure = true
}
