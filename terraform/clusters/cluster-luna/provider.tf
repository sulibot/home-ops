terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1.1"
    }

    local = {
#      source = "hashicorp/local"
    }
    random = {
      source  = "hashicorp/random"

    }
#    cloudinit = {
#      source  = "hashicorp/cloudinit"
#      version = "~> 2.3.4"
#    }
  }
}

provider "proxmox" {
  endpoint  = local.pve_endpoint
  api_token = "${local.pve_api_token_id}=${local.pve_api_token_secret}"
  
  # Comment or uncomment based on your self-signed cert usage
  insecure = true  # Set true for self-signed certificates (if needed)

  tmp_dir  = "/var/tmp"  # Optional customization

  ssh {
    agent    = true
    username = "root"  # Keep if SSH is required for certain operations
  }
}
