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

variable "cilium_daemonset_exists" {
  description = "Whether Cilium DaemonSet already exists in kube-system at plan time"
  type        = bool
  default     = false
}

variable "cluster_uid" {
  description = "Kubernetes cluster identity marker (kube-system namespace UID)"
  type        = string
  default     = ""
}

variable "bootstrap_run_token" {
  description = "Unique token to force cilium bootstrap execution for explicit bootstrap runs."
  type        = string
  default     = ""
}

locals {
  cilium_helmrelease_path = "${var.repo_root}/kubernetes/apps/tier-0-foundation/cilium/app/helmrelease.yaml"
  cilium_ocirepo_path     = "${var.repo_root}/kubernetes/apps/tier-0-foundation/cilium/app/ocirepository.yaml"
  cilium_bootstrap_path   = "${var.repo_root}/kubernetes/bootstrap/helmfile.yaml.gotmpl"
}

resource "null_resource" "bootstrap_cilium" {
  triggers = {
    kubeconfig_path        = var.kubeconfig_path
    cilium_daemonset_state = tostring(var.cilium_daemonset_exists)
    cluster_uid            = var.cluster_uid
    bootstrap_run_token    = var.bootstrap_run_token
    cilium_helmrelease_sha = filesha256(local.cilium_helmrelease_path)
    cilium_ocirepo_sha     = filesha256(local.cilium_ocirepo_path)
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

      CILIUM_VERSION="$(yq -r '.spec.chart.spec.version // ""' "${local.cilium_helmrelease_path}")"
      if [ -z "$CILIUM_VERSION" ] || [ "$CILIUM_VERSION" = "null" ]; then
        CILIUM_OCI_NAME="$(yq -r '.spec.chartRef.name // ""' "${local.cilium_helmrelease_path}")"
        if [ -n "$CILIUM_OCI_NAME" ] && [ "$CILIUM_OCI_NAME" != "null" ]; then
          CILIUM_VERSION="$(yq -r '
            select(.kind == "OCIRepository") | .spec.ref.tag // ""
          ' "${local.cilium_ocirepo_path}" | head -n1)"
        fi
      fi
      if [ -z "$CILIUM_VERSION" ] || [ "$CILIUM_VERSION" = "null" ]; then
        echo "ERROR: unable to resolve Cilium chart version from HelmRelease/OCIRepository" >&2
        exit 1
      fi
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
