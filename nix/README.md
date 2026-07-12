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
4. Deploy (and every change after):
   ```
   nixos-rebuild switch --flake ./nix#<hostname> \
     --target-host root@<ip> --build-host root@<ip>
   ```

## New VM guest

1. Unit using `modules/proxmox_nixos_vm` → `terragrunt apply` (boots a Debian
   bootstrap image with your SSH key).
2. Host file importing `profiles/vm.nix` + a `disko` disk layout.
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
