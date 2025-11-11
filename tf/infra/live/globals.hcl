locals {
  talos_version   = "v1.8.2"
  talos_platform  = "nocloud"
  image_cache_dir = "${get_repo_root()}/tf/infra/cache/talos"
}
