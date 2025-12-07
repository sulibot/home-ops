# Intel i915 + CDI setup

This repo bakes the Intel i915 system extension into the Talos installer and enables CDI paths in containerd so GPU devices can be exposed via CDI without extra feature gates.

## How it is built
- Custom installer is built with Talos `v1.12.0-beta.1` and these system extensions:
  - `ghcr.io/siderolabs/i915:20251125-v1.12.0-beta.1`
  - `ghcr.io/siderolabs/intel-ucode:20251111`
  - `ghcr.io/siderolabs/qemu-guest-agent:10.1.2`
  - `ghcr.io/siderolabs/util-linux-tools:2.41.2`
  - `ghcr.io/siderolabs/zfs:2.4.0-rc2-v1.12.0-beta.1`
  - `ghcr.io/siderolabs/nfsd:v1.12.0-beta.1`
  - `ghcr.io/siderolabs/nfsrahead:2.8.3`
  - `ghcr.io/sulibot/frr-talos-extension:v1.0.15`
- Images and versions come from `terraform/infra/live/common/versions.hcl` and are passed to `imager` via the Terragrunt local-exec in `1-talos-install-image-build/main.tf`.

## Runtime containerd CDI config
- We patch containerd to use writable CDI spec dirs:

  - File created on every node: `/etc/cri/conf.d/20-customization.part`
  - Content:
    ```
    [plugins."io.containerd.cri.v1.runtime"]
      cdi_spec_dirs = ["/var/cdi/static", "/var/cdi/dynamic"]
    ```
  - This is injected via Talos machine config patches in `terraform/infra/modules/talos_config/main.tf`.

- Kubelet feature gate `DevicePluginCDIDevices` is **not** enabled (it is deprecated and caused kubelet crashloops). CDI works without it as long as a CDI spec is present.

## What to expect on boot
- Talos initramfs logs will show the i915 extension being enabled and firmware bind-mounted.
- `/var/cdi/{static,dynamic}` will exist; drop CDI specs there (e.g., from a DaemonSet) to expose GPU devices to pods.
- Nodes should register normally; if kubelet crashloops with a CDI feature-gate error, verify the feature gate is absent from the rendered machine config.

## Troubleshooting
- If i915 devices are missing, confirm the extension image tag matches the Talos minor (`v1.12.0-beta.1`) and that the installer build pulled it successfully.
- If CDI specs are not found, check `talosctl get file /etc/cri/conf.d/20-customization.part` and containerd logs for the CDI spec directory configuration.
- For kubelet restarts mentioning `DevicePluginCDIDevices`, re-render configs to ensure that feature gate is removed.***
