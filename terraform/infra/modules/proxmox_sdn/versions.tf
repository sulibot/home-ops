terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.94.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }

  backend "local" {}
}
