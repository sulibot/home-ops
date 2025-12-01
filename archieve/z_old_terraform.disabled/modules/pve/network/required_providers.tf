terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.83.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.2.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.2"
    }
  }
}
