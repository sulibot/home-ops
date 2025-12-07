# Centralized version management for all clusters
# Update versions here and all clusters will inherit the changes

locals {
  # Talos versions
  talos_version      = "v1.12.0-beta.1"  # Supports K8s v1.35.0-alpha.3
  talos_platform     = "nocloud"
  talos_architecture = "amd64"

  # System extensions version (can lag Talos releases).
  # Align extensions with Talos v1.12.0-beta.1 (using per-extension images pinned from the bundle).
  extension_version = "v1.12.0-beta.1"

  # Kubernetes version (managed by Talos)
  kubernetes_version = "1.35.0-alpha.3"  # MutatingAdmissionPolicy is beta (enabled by default)

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
