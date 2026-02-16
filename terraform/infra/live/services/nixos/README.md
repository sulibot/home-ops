# NixOS Infrastructure on Proxmox

DRY Terraform/Terragrunt setup for managing NixOS VMs on Proxmox.

## Architecture

```
terraform/infra/
├── modules/nixos_vm/           # Reusable Terraform module
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── templates/              # Cloud-init templates
└── live/services/nixos/
    ├── common.hcl              # Shared configuration
    ├── build-server/           # NixOS build server (10.10.1.201)
    ├── kanidm01/               # Kanidm primary (10.10.1.211)
    ├── kanidm02/               # Kanidm replica (10.10.1.212)
    └── kanidm03/               # Kanidm replica (10.10.1.213)

nixos/
├── common.nix                  # Base NixOS config (imported by all)
├── build-server.nix            # Build server specific config
└── kanidm.nix                  # Kanidm server base config
```

## VMs

| VM | VMID | IP | Purpose | Resources |
|---|---|---|---|---|
| **nixos-build** | 10201 | 10.10.1.201 | Build server for Talos extensions | 8 CPU, 16GB RAM, 200GB |
| **kanidm01** | 10211 | 10.10.1.211 | Kanidm primary identity server | 4 CPU, 8GB RAM, 100GB |
| **kanidm02** | 10212 | 10.10.1.212 | Kanidm replica | 4 CPU, 8GB RAM, 100GB |
| **kanidm03** | 10213 | 10.10.1.213 | Kanidm replica | 4 CPU, 8GB RAM, 100GB |

## Usage

### Deploy all NixOS VMs

```bash
cd terraform/infra/live/services/nixos
terragrunt run-all apply
```

### Deploy specific VM

```bash
# Build server
cd build-server && terragrunt apply

# Kanidm servers
cd kanidm01 && terragrunt apply
cd kanidm02 && terragrunt apply
cd kanidm03 && terragrunt apply
```

### Update NixOS configuration

1. Edit the NixOS config file:
   ```bash
   vim ~/repos/github/home-ops/nixos/build-server.nix
   # or
   vim ~/repos/github/home-ops/nixos/kanidm.nix
   ```

2. Apply changes:
   ```bash
   cd build-server && terragrunt apply
   ```

3. SSH to the VM and rebuild:
   ```bash
   ssh root@10.10.1.201
   nixos-rebuild switch
   ```

## NixOS Build Server

The build server is configured for building Talos extensions and kernel modules.

### Build i915-sriov extension

```bash
ssh root@10.10.1.201

# Clone the extension repo
git clone https://github.com/sulibot/i915-sriov-talos-extension
cd i915-sriov-talos-extension

# Build using Docker (installed on build server)
docker build -t ghcr.io/sulibot/i915-sriov-talos-extension:latest .

# Push to registry
docker push ghcr.io/sulibot/i915-sriov-talos-extension:latest
```

### Installed tools

- Docker & container tools (buildah, skopeo, crane)
- Kernel build tools (gcc, make, kernel headers)
- Talos tools (talosctl, kubectl)
- Development tools (git, gh, nix-prefetch-git)

## Kanidm Identity Servers

Kanidm provides modern identity management and authentication.

### Architecture

- **kanidm01**: Primary server (read/write)
- **kanidm02/03**: Replicas (read-only, sync from primary)

### Access

```bash
# Web UI
https://auth.example.com

# CLI
ssh root@10.10.1.211
kanidm --help
```

### Replication

Kanidm01 is the primary server. Changes replicate automatically to kanidm02 and kanidm03.

## DRY Principles Applied

1. **Single NixOS module** (`modules/nixos_vm`) - used by all VMs
2. **Shared NixOS configs** (`nixos/common.nix`) - imported by all
3. **Common Terragrunt config** (`common.hcl`) - shared Proxmox/network settings
4. **Per-node customization** - via Terragrunt locals and NixOS overrides

## Maintenance

### Update NixOS channel

```bash
ssh root@<vm-ip>
nix-channel --update
nixos-rebuild switch --upgrade
```

### Backup Kanidm database

Backups run daily via restic (configured in `kanidm.nix`):

```bash
ls -lh /var/backups/kanidm/
```

### Destroy and recreate

```bash
cd <vm-dir>
terragrunt destroy
terragrunt apply
```

## References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Kanidm Documentation](https://kanidm.com/documentation.html)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)
