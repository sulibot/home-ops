locals {
  # Import centralized version management
  versions = read_terragrunt_config("${get_parent_terragrunt_dir()}/common/versions.hcl").locals

  # Version settings (from common/versions.hcl)
  talos_version      = local.versions.talos_version
  talos_platform     = local.versions.talos_platform
  talos_architecture = local.versions.talos_architecture
  kubernetes_version = local.versions.kubernetes_version

  # Infrastructure settings
  image_cache_dir = "${get_repo_root()}/terraform/infra/cache/talos"
}
