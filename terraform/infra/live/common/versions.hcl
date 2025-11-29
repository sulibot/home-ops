# Centralized version management for all clusters
# Update versions here and all clusters will inherit the changes

locals {
  # Talos versions
  talos_version      = "v1.12.0-beta.0"  # Supports K8s v1.35.0
  talos_platform     = "nocloud"
  talos_architecture = "amd64"

  # Kubernetes version (managed by Talos)
  kubernetes_version = "v1.35.0"  # MutatingAdmissionPolicy is beta (enabled by default)

  # Terraform provider versions
  provider_versions = {
    talos      = "~> 0.7.0"
    proxmox    = "~> 0.86.0"
    sops       = "~> 1.2.1"
    helm       = "~> 2.16.0"
    kubernetes = "~> 2.35.0"
    kubectl    = "~> 1.14.0"
    time       = "~> 0.12.0"
  }

  # Application versions
  cilium_version = "1.18.4"
  flux_version   = "latest"

  # Can be overridden per-cluster in cluster.hcl if needed
  # Example in cluster.hcl:
  #   talos_version = "v1.12.0"  # Override for this cluster only
}
