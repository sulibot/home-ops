terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }

  # Backend configuration managed by Terragrunt
  backend "local" {}
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}
