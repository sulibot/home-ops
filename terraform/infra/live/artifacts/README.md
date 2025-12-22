# Shared Talos Artifacts Pipeline

Enterprise-grade build and publish pipeline for Talos Linux images with custom FRR extension. These artifacts are **shared across all clusters** - built once, consumed by multiple clusters.

## Architecture

```
artifacts/
├── extension/   # Build FRR extension (optional - pre-built at ghcr.io)
├── images/      # Build installer (metal) + ISO (nocloud)
└── registry/    # Upload ISO to Proxmox
```

This follows enterprise patterns:
- **AWS AMI Pipeline**: build images → deploy to multiple accounts
- **HashiCorp Packer**: build once → deploy everywhere
- **Container Registry**: single image → multiple clusters

## Shared Artifacts Philosophy

**Key Principle**: All clusters use the same Talos version and extensions defined in `common/versions.hcl`.

**Benefits**:
- ✅ Build once → deploy to cluster-101, cluster-102, cluster-103
- ✅ Version consistency across all clusters
- ✅ Faster deployments (no per-cluster image builds)
- ✅ DRY (Don't Repeat Yourself)

**Image Naming** (version-based, not cluster-specific):
- Installer: `ghcr.io/sulibot/talos-frr-installer:v1.11.5`
- ISO: `talos-frr-v1.11.5-nocloud-amd64.iso`

## Pipeline Stages

### 1. Extension Build (`extension/`)

**Purpose**: Build custom FRR BGP routing extension for Talos

**Status**: Placeholder created (`extension/terragrunt.hcl`) - FRR extension currently pre-built at `ghcr.io/sulibot/frr-talos-extension:v1.0.18@sha256:b6cd79caf...`

**When to implement local builds**:
- Updating FRR version or daemon configuration
- Applying custom FRR patches
- Modifying Prometheus metrics exporter
- Requiring reproducible builds from source

**Output Contract** (when implemented):
- Image reference with pinned digest (not mutable tag)
- Semantic version tags for tracking
- Published to `ghcr.io/sulibot` registry

**Rollback**: Revert `common/install-schematic.hcl` → rebuild `artifacts/images/` → redeploy

### 2. Image Build (`images/`)

**Purpose**: Build all Talos image formats with identical extensions

**Inputs**:
- Talos version from `common/versions.hcl`
- System extensions from `common/install-schematic.hcl`:
  - `intel-ucode:20250812` - Intel microcode updates
  - `qemu-guest-agent:10.0.2` - Proxmox integration
  - `crun:1.24` - OCI runtime
  - `ctr:v2.1.5` - Container runtime interface
  - `frr:v1.0.18` - Custom BGP routing daemon

**Outputs**:
1. **Installer Image** (metal platform)
   - Format: Container image (OCI)
   - Platform: `metal` (bare metal installation)
   - Destination: `ghcr.io/sulibot/talos-frr-installer:v1.11.5`
   - Used by: Talos nodes during installation and upgrades

2. **Boot ISO** (nocloud platform)
   - Format: ISO file
   - Platform: `nocloud` (cloud-init for initial boot)
   - Destination: `build/talos-iso/talos-frr-v1.11.5-nocloud-amd64.iso`
   - Used by: Proxmox VMs for initial boot

**Platform Differences**:
- `metal`: Installer for physical disk (used by all nodes)
- `nocloud`: Cloud-init integration (used only for first boot)

Both formats contain **identical extensions** - only the platform integration differs.

### 3. Registry Upload (`registry/`)

**Purpose**: Distribute boot ISO to Proxmox infrastructure

**Dependencies**: Requires `images/` to complete first

**Actions**:
- Upload boot ISO to Proxmox Ceph storage (`resources` datastore)
- ISO becomes available on all Proxmox nodes automatically (Ceph replication)

**Infrastructure Targets**:
- Proxmox nodes: pve01, pve02, pve03
- Storage: Ceph-backed shared storage
- Path: `/mnt/pve/resources/template/iso/talos-frr-v1.11.5-nocloud-amd64.iso`

**Why Separate Upload?**
- Build can succeed even if infrastructure is temporarily unavailable
- Clear separation: artifact creation vs artifact distribution
- Enables testing builds locally before uploading

## Usage

### Build All Artifacts (Complete Pipeline)

```bash
cd terraform/infra/live/artifacts
terragrunt run-all apply
```

Executes the complete pipeline:
1. Build installer image → push to ghcr.io
2. Build boot ISO → write to local filesystem
3. Upload ISO → Proxmox Ceph storage

**Result**: All clusters can now use these artifacts for deployment.

### Build Only Images (Skip Upload)

```bash
cd terraform/infra/live/artifacts/images
terragrunt apply
```

Useful for:
- Testing image builds locally
- Building without Proxmox access
- Validating extension changes

### Rebuild Extension (Rare)

```bash
cd terraform/infra/live/artifacts/extension
terragrunt apply
```

Only needed when:
- Updating FRR version
- Changing extension configuration
- Modifying Prometheus metrics

## Triggers and Rebuilds

Images rebuild when any of these change:
- Talos version (`common/versions.hcl`)
- Extension versions or digests (`common/install-schematic.hcl`)
- Kernel arguments (`common/install-schematic.hcl`)
- Custom extension image references

**Note**: Installer image and ISO are **always** rebuilt (no caching) to ensure fresh artifacts.

## Outputs

### From `images/`:
- `installer_image`: Container image reference (e.g., `ghcr.io/sulibot/talos-frr-installer:v1.11.5`)
- `iso_path`: Local filesystem path to boot ISO
- `iso_name`: ISO filename
- `talos_version`: Talos version built

### From `registry/`:
- `talos_image_file_ids`: Map of Proxmox node → ISO datastore ID
- `talos_image_file_name`: ISO filename in Proxmox
- `talos_version`: Talos version published

## Cluster Dependencies

Cluster deployments depend on published artifacts:

```
artifacts/images/ ──┬──> clusters/cluster-101/config/  (needs installer_image)
                    │
artifacts/registry/ ┴──> clusters/cluster-101/compute/ (needs ISO file ID)
```

**Terragrunt automatically resolves these dependencies** - you don't need to manually sequence operations.

## Version Management

All clusters use the same version defined in `common/versions.hcl`:

```hcl
# common/versions.hcl
locals {
  talos_version      = "v1.11.5"
  kubernetes_version = "1.31.4"
}
```

**To upgrade all clusters**:
1. Update `common/versions.hcl`
2. Rebuild artifacts: `cd artifacts && terragrunt run-all apply`
3. Deploy to each cluster: `cd clusters/cluster-101 && terragrunt run-all apply`

This ensures version consistency across all clusters.

## Best Practices

1. **Build artifacts before cluster deployment**
   - Always run `artifacts/` pipeline before deploying new clusters
   - Ensures fresh images with latest extensions

2. **Use version-based naming**
   - Images are tagged with Talos version (e.g., `v1.11.5`)
   - Easy to identify which version is deployed

3. **Leverage dependency resolution**
   - Terragrunt automatically sequences: images → registry → compute → config → bootstrap
   - Use `terragrunt run-all` to execute in correct order

4. **Test image builds locally**
   - Build images without uploading to Proxmox
   - Validate extensions are included correctly

5. **Version lock extensions with SHA256 digests**
   - Ensures reproducibility across builds
   - Prevents supply chain attacks

## Troubleshooting

**Q: Installer build fails with "manifest unknown"**
A: Extension image reference is incorrect or digest is invalid. Verify with `crane manifest <image>`

**Q: Boot ISO won't boot in Proxmox**
A: Ensure VM has cloud-init drive attached (required for nocloud platform)

**Q: Extensions missing after installation**
A: System extensions are baked into installer at build time, not applied post-install. Rebuild artifacts.

**Q: QEMU guest agent not detected**
A: Guest agent requires extension in installer + service config in machine config. Check both are present.

**Q: How do I use a different Talos version for one cluster?**
A: This architecture uses shared artifacts - all clusters use the same version. To test new versions:
1. Build new installer manually (outside this pipeline)
2. Push to different registry tag (e.g., `v1.12.0-test`)
3. Update cluster to reference custom tag (requires code changes)

**Q: Can I build images without pushing to registry?**
A: Yes, but the pipeline expects to push. For local testing, use Docker save/load instead of push.

## Directory Structure

```
artifacts/
├── extension/
│   └── terragrunt.hcl          # FRR extension build
│
├── images/
│   └── terragrunt.hcl          # Installer + ISO build
│
└── registry/
    └── terragrunt.hcl          # ISO upload to Proxmox
```

**Dependencies**:
- `registry/` → `images/` (needs ISO path and name)
- `images/` → `common/versions.hcl` (Talos version)
- `images/` → `common/install-schematic.hcl` (extensions)

## Related Documentation

- [Multi-Cluster Refactoring Plan](../MULTI_CLUSTER_REFACTORING_PLAN.md) - Architecture decisions
- [clusters/](../clusters/) - Cluster deployments that consume these artifacts
- [common/versions.hcl](../common/versions.hcl) - Centralized version management
- [common/install-schematic.hcl](../common/install-schematic.hcl) - System extensions configuration
