terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }

  # Backend configuration managed by Terragrunt
  backend "local" {}
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}
