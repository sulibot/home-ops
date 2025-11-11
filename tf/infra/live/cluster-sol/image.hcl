locals {
  talos_extra_kernel_args = [
    "-init_on_alloc",
    "-init_on_free",
    "-selinux",
    "apparmor=0",
    "i915.enable_guc=3",
    "init_on_alloc=0",
    "init_on_free=0",
    "intel_iommu=on",
    "iommu=pt",
    "mitigations=off",
    "security=none",
    "sysctl.kernel.kexec_load_disabled=1",
    "talos.auditd.disabled=1"
  ]

  talos_system_extensions = [
    "siderolabs/intel-ucode"
  ]

  talos_patches = [
    {
      op    = "add"
      path  = "/machine/install/extraKernelArgs"
      value = ["console=ttyS0"]
    }
  ]
}
