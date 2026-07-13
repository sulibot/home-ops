# Homelab NixOS guests

Terraform (in `terraform/infra/`) creates the machines; this flake configures
them. No SSH bash provisioning — the split is deliberate:

| Concern | Lives in |
|---|---|
| Machine exists (CPU/RAM/disk/net/placement) | `terraform/infra/live/services/<name>/` + `common/lxc-service-catalog.hcl` |
| Everything running on it | `nix/hosts/<hostname>/` |

Tracks `nixos-25.11` (same as the workstation `nix-config` repo).

## New LXC guest

1. One-time per release: `scripts/fetch-nixos-lxc-template.sh` uploads the
   NixOS proxmoxLXC tarball to `resources:vztmpl/`.
2. Catalog entry (`os = "nixos"`) + a `live/services/<name>/terragrunt.hcl`
   using `modules/proxmox_nixos_lxc` → `terragrunt apply`.
3. `nix/hosts/<hostname>/default.nix` importing `profiles/lxc.nix`.
4. First boot: the template comes up with no network and no sshd (ostype
   `unmanaged` means PVE injects nothing). Bootstrap once from the PVE node:
   ```
   pct exec <vmid> -- /run/current-system/sw/bin/bash -c "
     ip link set eth0 up; ip addr add <ipv4-cidr> dev eth0
     ip route add default via <gw>; echo nameserver 10.255.0.53 > /etc/resolv.conf
     export NIX_CONFIG='experimental-features = nix-command flakes'
     export PATH=/run/current-system/sw/bin:\$PATH
     nixos-rebuild switch --flake github:sulibot/home-ops?dir=nix#<hostname>"
   ```
   The flake config makes networking + sshd declarative from then on.
5. Deploy (every change after):
   ```
   nixos-rebuild switch --flake ./nix#<hostname> \
     --target-host root@<ip> --build-host root@<ip>
   ```

## New VM guest

1. Unit using `modules/proxmox_nixos_vm` → `terragrunt apply` (boots a Debian
   bootstrap image with your SSH key).
2. Host file importing `profiles/vm.nix` + a `disko` disk layout
   (virtio disks are `/dev/vda`, not sda).
3. First install (once — wipes the disk, installs NixOS, builds on target):
   ```
   nix run github:nix-community/nixos-anywhere -- \
     --flake ./nix#<hostname> --build-on-remote root@<ip>
   ```
4. Thereafter, same `nixos-rebuild --target-host` as LXC.

## Secrets

Use sops-nix (input already wired) with the repo's existing age key and
`.sops.yaml` rules — same pipeline as everything else here.

## Builds

Small guests build on themselves (`--build-host` = target). Once
`nixbuild01` is up, point heavier builds at it via `nix.buildMachines` /
`--build-host root@10.200.0.201`.
