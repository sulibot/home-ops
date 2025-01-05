terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.2"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.2"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.4"
    }
  }
}

provider "proxmox" {
  endpoint  = local.pve_endpoint
  api_token = "${local.pve_api_token_id}=${local.pve_api_token_secret}"
  username  = local.pve_username
  password  = local.pve_password

  # because self-signed TLS certificate is in use
  #insecure = true
  tmp_dir  = "/var/tmp"

  ssh {
    agent = true
    username = "root"
  }
}
