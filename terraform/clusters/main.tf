terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70.0"  # Use ~> for better version control
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

