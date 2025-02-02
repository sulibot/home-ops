provider "proxmox" {
  endpoint  = local.pve_endpoint
  api_token = "${local.pve_api_token_id}=${local.pve_api_token_secret}"
  insecure  = true
  tmp_dir   = "/var/tmp"

  ssh {
    agent       = false
    private_key = file("~/.ssh/id_ed25519")
    username    = "root"
  }
}
