terraform {
  required_providers {
    proxmox  = { source = "bpg/proxmox",        version = ">= 0.83.0" }
    null     = { source = "hashicorp/null",     version = ">= 3.2.0" }
    external = { source = "hashicorp/external", version = "~> 2.2" }
    sops     = { source = "carlpett/sops",      version = "~> 1.3.0" }
  }
}