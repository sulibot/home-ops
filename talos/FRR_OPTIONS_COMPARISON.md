# FRR Extension: Three Approaches Compared

## The Problem

FRR is a **custom third-party system extension** (`ghcr.io/jsenecal/frr-talos-extension:latest`). The Talos Image Factory API **does not support custom extensions** in schematics - only official Siderolabs extensions are supported.

Testing confirms the API rejects `customExtensions` field:
```
field customExtensions not found in type schematic.Customization
```

## Three Options for Adding FRR

### Option 1: Image Factory Schematic with Overlay ❌ **NOT VIABLE**

**Concept:** Add FRR as an overlay in the Image Factory schematic

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/i915
      - siderolabs/qemu-guest-agent
  overlay:
    name: frr
    image: ghcr.io/jsenecal/frr-talos-extension:latest
```

**Why it doesn't work:**
- FRR is a **system extension**, not an **overlay**
- Overlays are for installation/boot process customization (firmware, bootloaders, hardware-specific)
- Extensions modify the root filesystem (drivers, kernel modules, tools)
- Using an extension image as an overlay is a category mismatch

**Verdict:** ❌ Architecturally incorrect approach

---

### Option 2: Custom Installer Image (Manual) ⚠️ **WORKS BUT MANUAL**

**Concept:** Build custom installer locally using Talos imager, push to registry

**Implementation:**
```bash
# 1. Build custom installer
docker run --rm \
  -v "${PWD}/_out:/out" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/siderolabs/imager:v1.11.5 \
  installer \
  --arch amd64 \
  --platform metal \
  --base-installer-image ghcr.io/siderolabs/installer:v1.11.5 \
  --system-extension-image ghcr.io/jsenecal/frr-talos-extension:latest

# 2. Load, tag, push to registry
docker load < _out/installer-amd64.tar
docker tag <image-id> ghcr.io/username/talos-installer-frr:v1.11.5
docker push ghcr.io/username/talos-installer-frr:v1.11.5

# 3. Update Terraform to use custom installer
# In talos-config module:
installer_image = "ghcr.io/username/talos-installer-frr:v1.11.5"
```

**Pros:**
- ✅ Fully supported by Talos
- ✅ Complete control over build process
- ✅ Works with any custom extension
- ✅ Can combine multiple custom extensions

**Cons:**
- ⚠️ Manual build process outside Terraform
- ⚠️ Must rebuild for each Talos version
- ⚠️ Requires Docker and registry access
- ⚠️ Not declarative in Terraform
- ⚠️ Version drift between Terraform state and actual image

**Best for:**
- One-time setup
- Testing custom extensions
- When you don't have CI/CD

**Provided files:**
- `talos/build-custom-installer.sh` - Build script

---

### Option 3: Custom Installer via Terraform ✅ **RECOMMENDED**

**Concept:** Use Terraform `null_resource` to build custom installer automatically

**Implementation:**
```hcl
# Module: terraform/infra/modules/talos_custom_installer/main.tf
resource "null_resource" "build_installer" {
  triggers = {
    talos_version = var.talos_version
    extensions    = join(",", var.custom_extensions)
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker run --rm -v "$TEMP_DIR:/out" \
        ghcr.io/siderolabs/imager:${var.talos_version} \
        installer --arch amd64 --platform metal \
        --system-extension-image ghcr.io/jsenecal/frr-talos-extension:latest

      docker load < $TEMP_DIR/installer-amd64.tar
      docker tag <id> ${var.output_registry}:${var.talos_version}
      docker push ${var.output_registry}:${var.talos_version}
    EOT
  }
}
```

**Usage:**
```bash
cd terraform/infra/live/cluster-101/custom-installer
terragrunt apply
```

**Pros:**
- ✅ Declarative in Terraform
- ✅ Automatic rebuilds on version changes
- ✅ Version tracked in Terraform state
- ✅ Repeatable and auditable
- ✅ Integrates with existing workflow
- ✅ Can add more extensions easily

**Cons:**
- ⚠️ Requires Docker on Terraform runner
- ⚠️ Requires registry credentials configured
- ⚠️ Build happens during `terraform apply` (can be slow)
- ⚠️ Triggers on every extension/version change

**Best for:**
- Production environments
- GitOps workflows
- Teams managing infrastructure as code
- When you want automated rebuilds

**Provided files:**
- `terraform/infra/modules/talos_custom_installer/main.tf` - Terraform module
- `terraform/infra/live/cluster-101/custom-installer/terragrunt.hcl` - Configuration

---

## Recommendation Matrix

| Scenario | Recommended Option |
|----------|-------------------|
| Quick testing/one-time setup | Option 2 (Manual) |
| Production with GitOps | Option 3 (Terraform) |
| CI/CD pipeline | Option 3 (Terraform) |
| Multiple custom extensions | Option 3 (Terraform) |
| No registry access | Option 2 (Manual, local push) |
| Need version tracking | Option 3 (Terraform) |

---

## Complete Setup (Option 3 - Recommended)

### 1. Configure Registry

Edit `terraform/infra/live/cluster-101/custom-installer/terragrunt.hcl`:

```hcl
inputs = {
  talos_version = local.versions.talos_version

  custom_extensions = [
    "ghcr.io/jsenecal/frr-talos-extension:latest",
  ]

  # Update with your registry
  output_registry = "ghcr.io/YOUR_USERNAME/talos-installer-frr"
}
```

### 2. Authenticate to Registry

```bash
# GitHub Container Registry example
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

### 3. Build Custom Installer

```bash
cd terraform/infra/live/cluster-101/custom-installer
terragrunt apply
```

This outputs: `installer_image = "ghcr.io/YOUR_USERNAME/talos-installer-frr:v1.11.5"`

### 4. Update Talos Config to Use Custom Installer

Find where your machine config sets the installer image and change from:

```hcl
# Image Factory installer (doesn't support custom extensions)
installer_image = "factory.talos.dev/installer/${schematic_id}:${talos_version}"
```

To:

```hcl
# Custom installer with FRR
installer_image = dependency.custom_installer.outputs.installer_image
```

### 5. Add FRR Configuration

Add to your machine config:

```yaml
---
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
environment:
  - ASN_LOCAL=4200001001  # Your BGP AS number
  - NODE_IP=10.10.10.10   # Node /32 IP
```

### 6. Deploy

```bash
cd terraform/infra/live/cluster-101
terragrunt run-all apply
```

### 7. Verify

```bash
talosctl -n <node-ip> get extensions
# Should show: frr
```

---

## Why Not Image Factory Schematic?

The Image Factory API **only supports**:
- `customization.extraKernelArgs` ✅
- `customization.systemExtensions.officialExtensions` ✅ (Siderolabs only)
- `customization.overlay` ✅ (for boot/hardware customization)

The Image Factory API **does NOT support**:
- `customization.customExtensions` ❌
- `customization.security.allow-unsigned-extensions` ❌

This is by design - Image Factory is for official, signed extensions only. Custom extensions require building your own installer.

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    OFFICIAL EXTENSIONS                      │
│  (siderolabs/i915, siderolabs/qemu-guest-agent, etc.)      │
│                                                             │
│              Use: Image Factory Schematic                   │
│         ✅ Supported by Image Factory API                   │
│         ✅ Automatically signed and verified                │
│         ✅ Version matched to Talos release                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   CUSTOM EXTENSIONS                         │
│         (ghcr.io/jsenecal/frr-talos-extension)             │
│                                                             │
│         Use: Custom Installer Image (imager)                │
│         ❌ NOT supported by Image Factory schematic         │
│         ✅ Build with talos imager tool                     │
│         ✅ Can automate with Terraform null_resource        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  HARDWARE CUSTOMIZATION                     │
│      (Raspberry Pi firmware, custom bootloaders)            │
│                                                             │
│              Use: Overlays in Schematic                     │
│         ✅ Supported by Image Factory API                   │
│         ✅ For boot/install process customization           │
└─────────────────────────────────────────────────────────────┘
```

---

## References

- [System Extensions - Talos v1.11](https://www.talos.dev/v1.11/talos-guides/configuration/system-extensions/)
- [Overlays - Talos v1.11](https://www.talos.dev/v1.10/advanced/overlays/)
- [Image Factory Documentation](https://www.talos.dev/v1.11/learn-more/image-factory/)
- [ExtensionServiceConfig](https://www.talos.dev/v1.11/reference/configuration/extensions/extensionserviceconfig/)
- [How to build a Talos system extension](https://www.siderolabs.com/blog/how-to-build-a-talos-system-extension/)
- [FRR Talos Extension](https://github.com/abckey/frr-talos-extension)
- [Siderolabs Extensions Repository](https://github.com/siderolabs/extensions)
- [Siderolabs Overlays Repository](https://github.com/siderolabs/overlays)
