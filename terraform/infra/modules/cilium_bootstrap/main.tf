terraform {
  backend "local" {}

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

variable "region" {
  description = "Deployment region (passed globally by root terragrunt config)"
  type        = string
  default     = "home-lab"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file for the target cluster"
  type        = string
}

variable "repo_root" {
  description = "Absolute repository root path"
  type        = string
}

locals {
  cilium_helmrelease_path = "${var.repo_root}/kubernetes/apps/tier-0-foundation/cilium/app/helmrelease.yaml"
  cilium_bootstrap_path   = "${var.repo_root}/kubernetes/bootstrap/helmfile.yaml.gotmpl"
}

resource "null_resource" "bootstrap_cilium" {
  triggers = {
    kubeconfig_path        = var.kubeconfig_path
    cilium_helmrelease_sha = filesha256(local.cilium_helmrelease_path)
    cilium_bootstrap_sha   = filesha256(local.cilium_bootstrap_path)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = <<-EOT
      set -euo pipefail

      if [ ! -f "${var.kubeconfig_path}" ]; then
        echo "ERROR: kubeconfig not found at ${var.kubeconfig_path}" >&2
        exit 1
      fi

      export KUBECONFIG="${var.kubeconfig_path}"

      echo "Waiting for Kubernetes API readiness before Cilium bootstrap..."
      timeout 300 bash -ec '
        until kubectl get --raw=/readyz >/dev/null 2>&1; do
          sleep 2
        done
      '

      CILIUM_VERSION=$(yq '.spec.chart.spec.version' "${local.cilium_helmrelease_path}")
      echo "Installing Gateway API CRDs + Cilium CNI v$CILIUM_VERSION via bootstrap unit..."
      CILIUM_VERSION="$CILIUM_VERSION" helmfile -f "${local.cilium_bootstrap_path}" sync
      echo "✓ Cilium bootstrap completed"
    EOT
  }
}

output "cilium_bootstrap_complete" {
  description = "Whether the Cilium bootstrap unit executed successfully"
  value       = null_resource.bootstrap_cilium.id != ""
}
