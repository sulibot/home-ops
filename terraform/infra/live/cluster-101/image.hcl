# This file can be used to override the default schematic configuration
# defined in common/schematic.hcl for this specific cluster.
#
# To override, uncomment and modify the locals block below:
#
# locals {
#   # Override kernel args
#   talos_extra_kernel_args = [
#     "-init_on_alloc",
#     "custom-arg=value",
#   ]
#
#   # Override system extensions
#   talos_system_extensions = [
#     "siderolabs/qemu-guest-agent",
#   ]
#
#   # Override patches
#   talos_patches = [
#     {
#       op    = "add"
#       path  = "/machine/install/extraKernelArgs"
#       value = ["console=ttyS0"]
#     }
#   ]
# }
#
# If not overridden here, values from common/schematic.hcl will be used.
