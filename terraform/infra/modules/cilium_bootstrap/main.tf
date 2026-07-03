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

variable "direct_routing_device" {
  description = "Optional network interface to use for Cilium direct routing."
  type        = string
  default     = ""
}

variable "ipv4_native_routing_cidr" {
  description = "Optional IPv4 native routing CIDR override for Cilium."
  type        = string
  default     = ""
}

variable "ipv6_native_routing_cidr" {
  description = "Optional IPv6 native routing CIDR override for Cilium."
  type        = string
  default     = ""
}

variable "operator_replicas" {
  description = "Optional Cilium operator replica count override."
  type        = number
  default     = 0
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
    direct_routing_device  = var.direct_routing_device
    ipv4_native_cidr       = var.ipv4_native_routing_cidr
    ipv6_native_cidr       = var.ipv6_native_routing_cidr
    operator_replicas      = tostring(var.operator_replicas)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      if [ ! -f "${var.kubeconfig_path}" ]; then
        echo "ERROR: kubeconfig not found at ${var.kubeconfig_path}" >&2
        exit 1
      fi

      export KUBECONFIG="${var.kubeconfig_path}"

echo "Waiting for Kubernetes API readiness before Cilium bootstrap..."
for i in {1..150}; do
  if kubectl --request-timeout=10s get --raw=/readyz >/dev/null 2>&1 || \
     kubectl --request-timeout=10s get nodes >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

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
      if command -v helmfile >/dev/null 2>&1; then
        HELMFILE=(helmfile)
      elif command -v nix >/dev/null 2>&1; then
        HELMFILE=(nix shell nixpkgs#helmfile --command helmfile)
      else
        echo "ERROR: helmfile is required. Install helmfile or make nix available." >&2
        exit 1
      fi

      echo "Installing Gateway API CRDs + Cilium CNI v$CILIUM_VERSION via bootstrap unit..."
      CILIUM_VERSION="$CILIUM_VERSION" \
      CILIUM_DIRECT_ROUTING_DEVICE="${var.direct_routing_device}" \
      CILIUM_IPV4_NATIVE_ROUTING_CIDR="${var.ipv4_native_routing_cidr}" \
      CILIUM_IPV6_NATIVE_ROUTING_CIDR="${var.ipv6_native_routing_cidr}" \
      CILIUM_OPERATOR_REPLICAS="${var.operator_replicas}" \
      "$${HELMFILE[@]}" -f "${local.cilium_bootstrap_path}" sync
      echo "✓ Cilium bootstrap completed"
    EOT
  }
}

output "cilium_bootstrap_complete" {
  description = "Whether the Cilium bootstrap unit executed successfully"
  value       = null_resource.bootstrap_cilium.id != ""
}
