# Centralized version management for all clusters
# Update versions here and all clusters will inherit the changes

locals {
  # Talos versions
  talos_version      = "v1.11.5"
  talos_platform     = "nocloud"
  talos_architecture = "amd64"

  # Kubernetes version (managed by Talos)
  kubernetes_version = "v1.31.4"

  # Can be overridden per-cluster in cluster.hcl if needed
  # Example in cluster.hcl:
  #   talos_version = "v1.12.0"  # Override for this cluster only
}
