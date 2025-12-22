# Multi-Cluster Refactoring Implementation Plan

## Executive Summary

Refactor Terraform structure from single-cluster to enterprise multi-cluster pattern using **Option 1A: Shared Artifacts with Pre-Built Registry Overrides**.

**Goal**: Enable DRY (Don't Repeat Yourself) deployment of multiple Talos Kubernetes clusters while maintaining flexibility for per-cluster version customization.

**Approach**: Extract shared artifact pipeline to top-level, use container registry for version management, support optional per-cluster overrides.

---

## Current State

### Directory Structure (Single Cluster)
```
terraform/infra/live/
├── common/                    # ✅ Shared (versions, SDN, firewall)
│   ├── versions.hcl
│   ├── install-schematic.hcl
│   ├── 0-sdn-setup/
│   └── 1-firewall/
│
└── cluster-101/               # ❌ Per-cluster (duplicates artifacts)
    ├── artifacts/             # Would be duplicated for cluster-102, 103, etc.
    │   ├── extension/        # FRR extension build
    │   ├── build/            # Installer + ISO build
    │   └── publish/          # ISO upload to Proxmox
    │
    └── cluster/               # ✅ Per-cluster (correct)
        ├── compute/          # VM creation
        ├── config/           # Talos configs
        └── bootstrap/        # K8s bootstrap
```

### Problem
To add cluster-102, you would need to:
1. Copy entire `cluster-101/` directory (6 folders × 3 pipelines = 18 folders)
2. Duplicate artifact build logic (extension, build, publish)
3. Build identical images multiple times (same Talos version, same extensions)
4. Maintain version consistency across multiple artifact pipelines

**This violates DRY principles and increases maintenance burden.**

---

## Target State

### Directory Structure (Multi-Cluster)
```
terraform/infra/live/
├── common/                          # Shared configuration
│   ├── versions.hcl                # ✅ Centralized version management
│   ├── install-schematic.hcl       # ✅ Shared extension definitions
│   ├── ipv6-prefixes.hcl           # ✅ IPv6 prefix allocation
│   ├── 0-sdn-setup/                # ✅ Shared SDN infrastructure
│   └── 1-firewall/                 # ✅ Shared firewall rules
│
├── artifacts/                       # NEW: Shared artifact pipeline
│   ├── extension/                  # Build FRR extension (optional)
│   ├── images/                     # Build installer + ISO (once)
│   └── registry/                   # Upload ISO to Proxmox (once)
│
└── clusters/                        # RENAMED: Multi-cluster deployments
    ├── cluster-101/                # Production (sol)
    │   ├── cluster.hcl             # Cluster definition + optional overrides
    │   ├── compute/                # Create VMs
    │   ├── config/                 # Generate Talos configs
    │   └── bootstrap/              # Bootstrap Kubernetes
    │
    ├── cluster-102/                # Staging (luna)
    │   ├── cluster.hcl
    │   ├── compute/
    │   ├── config/
    │   └── bootstrap/
    │
    └── cluster-103/                # Development (terra)
        ├── cluster.hcl
        ├── compute/
        ├── config/
        └── bootstrap/
```

### Benefits
- ✅ **True DRY**: Artifacts built once, consumed by all clusters
- ✅ **Version Consistency**: All clusters use same Talos version by default
- ✅ **Easy Scale**: Adding cluster-102 requires only `cluster.hcl` + deployment folders
- ✅ **CI/CD Efficiency**: Build once → deploy to multiple clusters
- ✅ **Clear Separation**: `artifacts/` = "What images?" vs `clusters/` = "What clusters?"

---

## Design Principles

### 1. Shared by Default, Override When Needed

**Default Behavior (90% of clusters):**
```hcl
# clusters/cluster-101/cluster.hcl
locals {
  cluster_name = "sol"
  cluster_id   = 101
  # No artifact_overrides - automatically uses shared artifacts/
}
```

**Custom Version (10% of clusters - testing/special needs):**
```hcl
# clusters/cluster-102/cluster.hcl
locals {
  cluster_name = "luna"
  cluster_id   = 102

  # Optional: Override to use different Talos version
  artifact_overrides = {
    installer_image = "ghcr.io/sulibot/talos-frr-installer:v1.12.0-frr-1.0.19"
    iso_file_id     = "resources:iso/talos-frr-v1.12.0-nocloud-amd64.iso"
  }
}
```

### 2. Container Registry as Version Source

**Shared artifacts/ builds default version:**
- Talos v1.11.5 → `ghcr.io/sulibot/talos-frr-installer:v1.11.5`
- ISO → `resources:iso/talos-frr-v1.11.5-nocloud-amd64.iso`

**Custom versions pre-built externally:**
- Build manually or via CI/CD
- Push to registry with version tag
- Clusters reference by tag in `artifact_overrides`

**No Terraform duplication for custom versions** - they're just container images.

### 3. Conditional Dependencies

Clusters use shared artifacts by default, but skip dependency if override exists:

```hcl
# clusters/*/compute/terragrunt.hcl
dependency "image" {
  config_path = "../../../artifacts/registry"

  # Skip if cluster has pre-built override
  skip = try(local.cluster_config.artifact_overrides.iso_file_id != null, false)
}

inputs = {
  talos_image_file_id = try(
    local.cluster_config.artifact_overrides.iso_file_id,  # Use override if exists
    dependency.image.outputs.talos_image_file_ids[...]     # Otherwise shared
  )
}
```

---

## Implementation Steps

### Phase 1: Create Shared Artifacts Structure

**1.1 Create directories:**
```bash
cd terraform/infra/live
mkdir -p artifacts/{extension,images,registry}
```

**1.2 Move extension build (optional):**
```bash
mv cluster-101/artifacts/extension/terragrunt.hcl artifacts/extension/
```

**1.3 Move image build:**
```bash
mv cluster-101/artifacts/build/terragrunt.hcl artifacts/images/
```

**1.4 Move ISO upload:**
```bash
mv cluster-101/artifacts/publish/terragrunt.hcl artifacts/registry/
```

**1.5 Remove old artifacts directory:**
```bash
rm -rf cluster-101/artifacts
```

---

### Phase 2: Update Artifact Configurations

**2.1 Update `artifacts/images/terragrunt.hcl`:**

Change from cluster-specific to version-based naming:
```hcl
# OLD (cluster-specific):
installer_registry = "ghcr.io/sulibot/${local.cluster_config.cluster_name}-talos-installer-frr"
iso_name = "${local.cluster_config.cluster_name}-talos-${local.versions.talos_version}-nocloud-amd64.iso"

# NEW (version-based):
installer_registry = "ghcr.io/sulibot/talos-frr-installer"
iso_name = "talos-frr-${local.versions.talos_version}-nocloud-amd64.iso"
```

Remove `cluster.hcl` dependency (not needed at artifact level):
```hcl
locals {
  versions          = read_terragrunt_config(find_in_parent_folders("common/versions.hcl")).locals
  install_schematic = read_terragrunt_config(find_in_parent_folders("common/install-schematic.hcl")).locals
  # Remove: cluster_config = read_terragrunt_config(...)
}
```

**2.2 Update `artifacts/registry/terragrunt.hcl`:**

Same changes - remove cluster-specific references.

**2.3 Update `artifacts/extension/terragrunt.hcl`:**

Already version-based (no changes needed).

---

### Phase 3: Restructure Cluster Deployments

**3.1 Create clusters directory and move cluster-101:**
```bash
cd terraform/infra/live
mkdir -p clusters
mv cluster-101 clusters/
```

**3.2 Rename cluster-101/cluster/ to remove extra nesting:**
```bash
cd clusters/cluster-101
mv cluster/* .
rmdir cluster
```

**Result:**
```
clusters/cluster-101/
├── cluster.hcl
├── compute/
├── config/
└── bootstrap/
```

---

### Phase 4: Update Cluster Dependencies

**4.1 Update `clusters/cluster-101/cluster.hcl`:**

Add optional `artifact_overrides` section (empty by default):
```hcl
locals {
  cluster_name   = "sol"
  cluster_id     = 101
  controlplanes  = 3
  workers        = 3
  proxmox_nodes  = ["pve01", "pve02", "pve03"]
  proxmox_hostnames = ["pve01.sulibot.com", "pve02.sulibot.com", "pve03.sulibot.com"]
  storage_default = "rbd-vm"

  network = {
    bridge_public = "vmbr0"
    vlan_public   = 101
    bridge_mesh   = "vnet101"
    vlan_mesh     = 0
    public_mtu    = 1500
    mesh_mtu      = 8930
    use_sdn       = true
  }

  node_overrides = {
    # GPU passthrough configs...
  }

  # Optional: Override artifact versions (uncomment to customize)
  artifact_overrides = {
    # installer_image = "ghcr.io/sulibot/talos-frr-installer:v1.12.0"
    # iso_file_id     = "resources:iso/talos-frr-v1.12.0.iso"
  }
}
```

**4.2 Update `clusters/cluster-101/compute/terragrunt.hcl`:**

Change dependency paths to reference shared artifacts:
```hcl
# OLD:
dependency "image" {
  config_path = "../../artifacts/publish"
}

# NEW:
dependency "image" {
  config_path = "../../../artifacts/registry"

  # Skip dependency if cluster uses pre-built override
  skip = try(local.cluster_config.artifact_overrides.iso_file_id != null, false)

  mock_outputs = {
    talos_image_file_ids = {
      "pve01" = "resources:iso/mock-talos-image.iso"
    }
    talos_image_file_name = "mock-talos-image.iso"
    talos_image_id        = "mock-schematic-id"
    talos_version         = "v1.11.5"
    kubernetes_version    = "v1.31.4"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
```

Update inputs to use override if present:
```hcl
inputs = merge(
  {
    # ... other inputs ...

    # Use override if specified, otherwise use shared artifact
    talos_image_file_id = try(
      local.cluster_config.artifact_overrides.iso_file_id,
      dependency.image.outputs.talos_image_file_ids[local.cluster_config.proxmox_nodes[0]]
    )

    talos_version = try(
      local.cluster_config.artifact_overrides.talos_version,
      dependency.image.outputs.talos_version
    )

    kubernetes_version = try(
      local.cluster_config.artifact_overrides.kubernetes_version,
      dependency.image.outputs.kubernetes_version
    )
  }
)
```

**4.3 Update `clusters/cluster-101/config/terragrunt.hcl`:**

Change artifact dependency paths:
```hcl
# OLD:
dependency "image" {
  config_path = "../../artifacts/publish"
}

dependency "custom_installer" {
  config_path = "../../artifacts/build"
}

# NEW:
dependency "image" {
  config_path = "../../../artifacts/registry"
  skip = try(local.cluster_config.artifact_overrides.iso_file_id != null, false)
  # ... mock_outputs ...
}

dependency "custom_installer" {
  config_path = "../../../artifacts/images"
  skip = try(local.cluster_config.artifact_overrides.installer_image != null, false)

  mock_outputs = {
    installer_image = "ghcr.io/sulibot/talos-frr-installer:v1.11.5"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
```

Update installer image input:
```hcl
inputs = {
  # ... other inputs ...

  # Use override if specified, otherwise use shared artifact
  installer_image = try(
    local.cluster_config.artifact_overrides.installer_image,
    dependency.custom_installer.outputs.installer_image
  )
}
```

**4.4 Update `clusters/cluster-101/bootstrap/terragrunt.hcl`:**

Change config dependency path:
```hcl
# OLD:
dependency "config" {
  config_path = "../config"
}

# NEW:
dependency "config" {
  config_path = "../config"
}
# (No change - relative path remains the same)
```

---

### Phase 5: Update Documentation

**5.1 Create `artifacts/README.md`:**

Document the shared artifact pipeline (see detailed content below).

**5.2 Update `clusters/cluster-101/README.md`:**

Update paths to reflect new structure:
```markdown
# Cluster-101 Deployment

Enterprise-grade Talos Linux Kubernetes cluster with BGP routing.

## Structure

```
cluster-101/
├── cluster.hcl         # Cluster definition + optional overrides
├── compute/            # Proxmox VMs
├── config/             # Talos machine configs
└── bootstrap/          # Kubernetes bootstrap
```

## Quick Start

**Build Shared Images (run once):**
```bash
cd ../../artifacts
terragrunt run-all apply
```

**Deploy Cluster:**
```bash
cd ../clusters/cluster-101
terragrunt run-all apply
```

See [../../artifacts/README.md](../../artifacts/README.md) for artifact details.
```

**5.3 Create `terraform/infra/live/README.md`:**

Document overall structure (see detailed content below).

---

### Phase 6: Validation

**6.1 Validate artifacts pipeline:**
```bash
cd terraform/infra/live/artifacts
terragrunt run-all plan
```

**Expected output:**
- ✓ Extension build plan (if enabled)
- ✓ Image build plan (installer + ISO)
- ✓ Registry upload plan (ISO to Proxmox)

**6.2 Validate cluster-101 deployment:**
```bash
cd terraform/infra/live/clusters/cluster-101
terragrunt run-all plan
```

**Expected output:**
- ✓ Compute dependency resolves to `../../../artifacts/registry`
- ✓ Config dependency resolves to `../../../artifacts/images`
- ✓ No errors about missing dependencies

**6.3 Test artifact override (optional):**

Create test override in cluster.hcl:
```hcl
artifact_overrides = {
  installer_image = "ghcr.io/sulibot/talos-frr-installer:test-override"
  iso_file_id     = "resources:iso/test-override.iso"
}
```

Run plan:
```bash
cd clusters/cluster-101/compute
terragrunt plan
```

**Expected behavior:**
- ✓ Dependency to `artifacts/registry` is skipped
- ✓ Inputs use override values instead of dependency outputs

---

## Adding New Clusters

### Scenario: Add cluster-102 (Staging)

**Step 1: Copy cluster structure**
```bash
cd terraform/infra/live/clusters
cp -r cluster-101 cluster-102
```

**Step 2: Update cluster.hcl**
```bash
cat > cluster-102/cluster.hcl <<'EOF'
locals {
  cluster_name   = "luna"
  cluster_id     = 102
  controlplanes  = 3
  workers        = 3
  proxmox_nodes  = ["pve01", "pve02", "pve03"]
  proxmox_hostnames = ["pve01.sulibot.com", "pve02.sulibot.com", "pve03.sulibot.com"]
  storage_default = "rbd-vm"

  network = {
    bridge_public = "vmbr0"
    vlan_public   = 102
    bridge_mesh   = "vnet102"
    vlan_mesh     = 0
    public_mtu    = 1500
    mesh_mtu      = 8930
    use_sdn       = true
  }

  node_overrides = {}

  # Uses shared artifacts by default (same version as cluster-101)
  artifact_overrides = {}
}
EOF
```

**Step 3: Deploy**
```bash
cd cluster-102
terragrunt run-all apply
```

**Result:** cluster-102 uses the same Talos images built by `artifacts/` - no duplication!

---

## Custom Version Workflow

### Scenario: cluster-102 needs to test Talos v1.12.0

**Step 1: Build custom installer (outside Terraform)**
```bash
cd /tmp/custom-talos-build

# Build installer with Talos v1.12.0 and FRR v1.0.19
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/out \
  ghcr.io/siderolabs/imager:v1.12.0 \
  installer --arch amd64 --platform metal \
  --system-extension-image ghcr.io/siderolabs/intel-ucode:20250812@sha256:... \
  --system-extension-image ghcr.io/sulibot/talos-frr-extension:v1.0.19 \
  --base-installer-image factory.talos.dev/installer/...:v1.12.0

# Load, tag, and push
LOADED_IMAGE=$(docker load < installer-amd64.tar | sed -n 's/^Loaded image: //p')
docker tag "$LOADED_IMAGE" ghcr.io/sulibot/talos-frr-installer:v1.12.0-frr-1.0.19
docker push ghcr.io/sulibot/talos-frr-installer:v1.12.0-frr-1.0.19
```

**Step 2: Build and upload boot ISO (if needed)**
```bash
# Build ISO
docker run --rm \
  -v $(pwd):/out \
  ghcr.io/siderolabs/imager:v1.12.0 \
  iso --arch amd64 --platform nocloud \
  --system-extension-image ghcr.io/sulibot/talos-frr-extension:v1.0.19 \
  --base-installer-image factory.talos.dev/installer/...:v1.12.0

# Upload to Proxmox (via Proxmox UI or Ansible)
scp nocloud-amd64.iso root@pve01:/mnt/pve/resources/template/iso/talos-frr-v1.12.0-nocloud-amd64.iso
```

**Step 3: Update cluster-102 to use custom artifacts**
```hcl
# clusters/cluster-102/cluster.hcl
locals {
  cluster_name = "luna"
  cluster_id   = 102

  # Override to use custom Talos v1.12.0
  artifact_overrides = {
    installer_image = "ghcr.io/sulibot/talos-frr-installer:v1.12.0-frr-1.0.19"
    iso_file_id     = "resources:iso/talos-frr-v1.12.0-nocloud-amd64.iso"
    talos_version      = "v1.12.0"
    kubernetes_version = "v1.32.0"
  }
}
```

**Step 4: Deploy cluster-102**
```bash
cd clusters/cluster-102
terragrunt run-all apply
```

**Result:** cluster-102 uses v1.12.0, cluster-101 continues using v1.11.5. No Terraform duplication!

---

## Risk Mitigation

### Risk 1: Image Name Collision

**Scenario:** Multiple clusters share same ISO name in Proxmox

**Before Refactoring:**
- `sol-talos-v1.11.5-nocloud-amd64.iso` (cluster-101 specific)
- `luna-talos-v1.11.5-nocloud-amd64.iso` (cluster-102 specific)

**After Refactoring:**
- `talos-frr-v1.11.5-nocloud-amd64.iso` (shared by all clusters using v1.11.5)

**Why This Is Safe:**
- Boot ISOs are used only for initial VM boot (cloud-init)
- After first boot, VMs pull installer from registry (versioned)
- Same ISO can boot multiple clusters (cloud-init differentiates via VM-specific config)

**Mitigation:** Acceptable - this is standard practice for cloud images.

### Risk 2: Concurrent Artifact Builds

**Scenario:** Two people run `terragrunt apply` in `artifacts/` simultaneously

**Impact:**
- Both builds push to same registry tag (last one wins)
- Potential race condition on ISO upload

**Mitigation:**
- Use CI/CD for artifact builds (single source of truth)
- Or use locking mechanism (Terragrunt supports remote state locking)
- For local development, communicate in team chat before artifact rebuild

### Risk 3: Breaking Change in Shared Artifacts

**Scenario:** Upgrade `artifacts/` to Talos v1.12.0, breaking cluster-101

**Impact:**
- cluster-101 expects v1.11.5, but artifact rebuild changes version

**Mitigation:**
1. **Pin in cluster.hcl override** (during transition period):
   ```hcl
   artifact_overrides = {
     installer_image = "ghcr.io/sulibot/talos-frr-installer:v1.11.5"
   }
   ```

2. **Test in staging first**:
   - Upgrade artifacts/ to v1.12.0
   - Deploy cluster-102 (staging)
   - Validate
   - Override cluster-101 to v1.12.0
   - Deploy cluster-101 (production)

3. **Use immutable tags**:
   - Tag with SHA256: `ghcr.io/.../talos-frr-installer:v1.11.5-sha256-abc123`
   - Prevents accidental overwrites

### Risk 4: State File Conflicts

**Scenario:** Moving directories breaks Terraform state paths

**Impact:**
- Terraform thinks resources need to be recreated

**Mitigation:**
- Terragrunt uses `path_relative_to_include()` for state paths:
  ```hcl
  path = "terragrunt-cache/${path_relative_to_include()}/terraform.tfstate"
  ```
- State files are isolated by path:
  - `terragrunt-cache/live/artifacts/images/terraform.tfstate`
  - `terragrunt-cache/live/clusters/cluster-101/compute/terraform.tfstate`
- Moving `cluster-101/` → `clusters/cluster-101/` creates new state path
- **Solution:** Use `terragrunt state mv` to migrate state, or destroy/recreate (safe for VMs)

---

## Success Criteria

After implementation, verify:

✅ **Artifacts built once, consumed by all clusters**
```bash
cd artifacts && terragrunt run-all apply
# Should build images once, not per-cluster
```

✅ **Adding new cluster requires only cluster.hcl + deployment files**
```bash
cp -r clusters/cluster-101 clusters/cluster-102
vim clusters/cluster-102/cluster.hcl  # Edit cluster_name and cluster_id
cd clusters/cluster-102 && terragrunt run-all apply
# Should deploy cluster-102 without rebuilding images
```

✅ **No duplication of image build logic**
```bash
find clusters/ -name "artifacts" -type d
# Should return empty (no per-cluster artifacts/)
```

✅ **Clear naming: artifacts/ vs clusters/**
```bash
ls -d terraform/infra/live/{artifacts,clusters}
# Should show both directories at top level
```

✅ **Backward compatible (cluster-101 keeps working)**
```bash
cd clusters/cluster-101 && terragrunt run-all plan
# Should show no changes (state preserved)
```

✅ **Version consistency enforced automatically**
```bash
cd artifacts && terragrunt output talos_version
cd clusters/cluster-101/compute && terragrunt output talos_version
# Should match (unless override in cluster.hcl)
```

✅ **Overrides work correctly**
```hcl
# Test: Add override to cluster.hcl
artifact_overrides = {
  installer_image = "ghcr.io/sulibot/talos-frr-installer:test"
}
# Run: terragrunt plan
# Verify: Dependency skipped, override used
```

---

## Rollback Plan

If refactoring fails, revert using:

```bash
cd terraform/infra/live

# Restore original structure
mv artifacts cluster-101/
mv clusters/cluster-101 .
rmdir clusters

# Revert dependency paths in cluster-101/
git checkout cluster-101/*/terragrunt.hcl

# Verify
cd cluster-101 && terragrunt run-all plan
```

State files remain intact (isolated by path), so rollback is safe.

---

## Files to Modify

### Create New Files:
1. `terraform/infra/live/artifacts/extension/terragrunt.hcl` (moved from cluster-101)
2. `terraform/infra/live/artifacts/images/terragrunt.hcl` (moved from cluster-101, updated)
3. `terraform/infra/live/artifacts/registry/terragrunt.hcl` (moved from cluster-101, updated)
4. `terraform/infra/live/artifacts/README.md` (new documentation)
5. `terraform/infra/live/README.md` (new documentation)

### Move Directories:
6. `cluster-101/` → `clusters/cluster-101/`
7. `cluster-101/cluster/*` → `clusters/cluster-101/*` (flatten)

### Update Existing Files:
8. `clusters/cluster-101/cluster.hcl` - add `artifact_overrides` section
9. `clusters/cluster-101/compute/terragrunt.hcl` - update dependency paths + conditional logic
10. `clusters/cluster-101/config/terragrunt.hcl` - update dependency paths + conditional logic
11. `clusters/cluster-101/bootstrap/terragrunt.hcl` - update dependency path (no change needed)
12. `clusters/cluster-101/README.md` - update paths and instructions

### Delete:
13. `cluster-101/artifacts/` (moved to top-level)

---

## Timeline Estimate

- **Phase 1**: Create shared artifacts structure - **10 minutes**
- **Phase 2**: Update artifact configurations - **15 minutes**
- **Phase 3**: Restructure cluster deployments - **10 minutes**
- **Phase 4**: Update cluster dependencies - **30 minutes**
- **Phase 5**: Update documentation - **20 minutes**
- **Phase 6**: Validation - **15 minutes**

**Total**: ~1.5 hours (for careful, tested implementation)

---

## Next Steps

1. ✅ Review this plan document
2. ⏭️ Execute Phase 1: Create shared artifacts structure
3. ⏭️ Execute Phase 2: Update artifact configurations
4. ⏭️ Execute Phase 3: Restructure cluster deployments
5. ⏭️ Execute Phase 4: Update cluster dependencies
6. ⏭️ Execute Phase 5: Update documentation
7. ⏭️ Execute Phase 6: Validation
8. ⏭️ Commit changes to git
9. ⏭️ Add cluster-102 to demonstrate multi-cluster capability

---

## Enterprise Pattern Validation

This refactoring aligns with enterprise infrastructure patterns:

✅ **AWS AMI Pipeline**: Build AMI once → launch multiple EC2 instances
✅ **HashiCorp Packer**: Packer builds → Terraform deploys
✅ **Kubernetes**: Container registry → multiple clusters pull same images
✅ **Immutable Infrastructure**: Images are immutable, clusters are mutable
✅ **DRY Principle**: Don't Repeat Yourself - shared artifact pipeline
✅ **Separation of Concerns**: Artifact generation vs cluster deployment

**Confidence Level**: High - This is a well-established pattern in production environments.
