# Centralized version management for all clusters
# Update versions here and all clusters will inherit the changes

locals {
  # Talos versions
  talos_version      = "v1.12.1"  # Fixes CephFS kernel 6.12 deadlock bug
  talos_platform     = "nocloud"
  talos_architecture = "amd64"

  # System extensions version (can lag Talos releases).
  # Align extensions with Talos v1.12.1
  extension_version = "v1.12.1"

  # Kubernetes version (managed by Talos)
  kubernetes_version = "1.34.1"  # Current K8s version for Talos v1.12.1

  # Terraform provider versions
  provider_versions = {
    talos      = "~> 0.9.0"
    proxmox    = "~> 0.89.0"
    sops       = "~> 1.3.0"
    helm       = "~> 3.1.1"
    kubernetes = "~> 3.0.0"
    kubectl    = "~> 1.14.0"
    time       = "~> 0.13.1"
  }

  # Application versions
  cilium_version = "1.18.4"
  flux_version   = "latest"

  # Can be overridden per-cluster in cluster.hcl if needed
  # Example in cluster.hcl:
  #   talos_version = "v1.12.0"  # Override for this cluster only
}
