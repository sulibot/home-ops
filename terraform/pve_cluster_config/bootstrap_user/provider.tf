terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.77.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~>1.1.1"
    }

  }

#  required_version = "~> 1.3.0"
}
