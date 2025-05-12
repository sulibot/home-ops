terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.77.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.1.1"
    }
    local = {
      source = "hashicorp/local"
    }
#    random = {
#      source  = "hashicorp/random"
#      version = "~> 3.6.2"
#    }
#    cloudinit = {
#      source  = "hashicorp/cloudinit"
#      version = "~> 2.3.4"
#    }
  }
}

output "proxmox_provider" {
  value = {
    endpoint  = local.pve_endpoint
    api_token = "${local.pve_api_token_id}=${local.pve_api_token_secret}"
  }
}
