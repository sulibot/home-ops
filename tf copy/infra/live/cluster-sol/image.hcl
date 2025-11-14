locals {
  # Source of truth: /Users/sulibot/repos/github/home-ops/talos/schematic.yaml.j2
  schematic_yaml = yamldecode(file("${get_terragrunt_dir()}/../../../../talos/schematic.yaml.j2"))

  talos_extra_kernel_args = local.schematic_yaml.customization.extraKernelArgs
  talos_system_extensions = local.schematic_yaml.customization.systemExtensions.officialExtensions

  talos_patches = [
    {
      op    = "add"
      path  = "/machine/install/extraKernelArgs"
      value = ["console=ttyS0"]
    }
  ]
}
