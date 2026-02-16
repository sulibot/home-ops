terraform {
  backend "local" {}

  required_version = ">= 1.5.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.0"
    }
  }
}
