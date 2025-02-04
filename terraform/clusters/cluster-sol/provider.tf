provider "proxmox" {
  endpoint  = data.sops_file.auth-secrets.data["pve_endpoint"]
  username    = "root@pam"
  password    = "${data.sops_file.auth-secrets.data["pve_password"]}"
  #api_token = "${data.sops_file.auth-secrets.data["pve_api_token_id"]}=${data.sops_file.auth-secrets.data["pve_api_token_secret"]}"
  insecure  = true
  tmp_dir   = "/var/tmp"

  ssh {
    agent       = false
    private_key = file("~/.ssh/id_ed25519")
    username    = "root"
  }
}

provider "sops" {}

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70.1"
    }
    sops = {
      source  = "carlpett/sops"
    }
  }
}

data "sops_file" "auth-secrets" {
  source_file = "${path.module}/../common/secrets.sops.yaml"
}