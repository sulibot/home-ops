# Custom Talos Installer Build (DISABLED)

This directory contains the infrastructure for building custom Talos installer images with third-party extensions.

## Current Status: DISABLED

The custom installer build has been disabled in favor of using the official Talos image factory with the BIRD2 extension.

The `terragrunt.hcl` file has been renamed to `terragrunt.hcl.disabled` to prevent it from running during `terragrunt run-all` commands.

## When to Use Custom Builds

Custom installer builds are required when:
- Using third-party extensions not available in the official siderolabs registry
- Building extensions from custom forks
- Testing unreleased extension versions

## How to Re-enable

To switch back to custom installer builds (e.g., to use FRR extension instead of BIRD2):

1. **Rename the file back:**
   ```bash
   mv terragrunt.hcl.disabled terragrunt.hcl
   ```

2. **Update the install-schematic.hcl:**
   ```hcl
   # In terraform/infra/live/common/install-schematic.hcl
   install_custom_extensions = [
     "ghcr.io/sulibot/frr-talos-extension:v1.0.15",
   ]
   ```

3. **Update machine-config-generate/terragrunt.hcl:**
   ```hcl
   # Uncomment the custom_installer dependency block
   dependency "custom_installer" {
     config_path = "../1-talos-install-image-build"
     # ...
   }

   # Change installer_image input back to:
   installer_image = dependency.custom_installer.outputs.installer_image
   ```

4. **Run the build:**
   ```bash
   cd terraform/infra/live/cluster-101/1-talos-install-image-build
   terragrunt apply
   ```

## Factory vs Custom Builds

| Feature | Factory Build | Custom Build |
|---------|---------------|--------------|
| **Speed** | Fast (pre-built images) | Slower (builds on-demand) |
| **Extensions** | Official siderolabs only | Any custom extension |
| **Maintenance** | Automatic updates | Manual version management |
| **Registry** | factory.talos.dev | ghcr.io/sulibot (custom) |
| **Use Case** | Production (BIRD2) | Development/Testing (FRR fork) |

## Current Architecture (BIRD2)

Using factory-built images with official BIRD2 extension:
- Extension: `ghcr.io/siderolabs/bird2:2.17.1`
- Installer: `factory.talos.dev/installer/${schematic_id}:${version}`
- Build time: None (uses pre-built images)

## Previous Architecture (FRR)

Custom-built installer with FRR fork:
- Extension: `ghcr.io/sulibot/frr-talos-extension:v1.0.15`
- Installer: `ghcr.io/sulibot/sol-talos-installer-frr:v1.12.0-beta.0`
- Build time: ~5-10 minutes per build
