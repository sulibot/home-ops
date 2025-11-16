# Default Talos schematic configuration for all clusters
# Can be overridden by creating schematic.hcl in the cluster directory

locals {
  # Source of truth: /Users/sulibot/repos/github/home-ops/talos/common/schematic.yaml.j2
  schematic_yaml = yamldecode(file("${get_repo_root()}/talos/common/schematic.yaml.j2"))

  talos_extra_kernel_args = local.schematic_yaml.customization.extraKernelArgs
  talos_system_extensions = local.schematic_yaml.customization.systemExtensions.officialExtensions

  # Default patches applied to all clusters
  talos_patches = [
    {
      op    = "add"
      path  = "/machine/install/extraKernelArgs"
      value = ["console=ttyS0"]
    }
  ]
}
