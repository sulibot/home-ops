# Option 3 Implementation Guide: Terraform-Automated Custom Installer

This guide walks through implementing the Terraform-automated custom installer with FRR extension.

## Prerequisites

1. **Docker Desktop** - Must be running
2. **GitHub Personal Access Token** - With `write:packages` permission
3. **Registry Access** - Authenticated to ghcr.io

## Step 1: Start Docker Desktop

```bash
# Start Docker Desktop (macOS)
open -a Docker

# Wait for Docker to be ready
docker info
```

## Step 2: Authenticate to GitHub Container Registry

Create a GitHub Personal Access Token (if you don't have one):
- Go to https://github.com/settings/tokens
- Click "Generate new token (classic)"
- Select scope: `write:packages`
- Copy the token

Login to GHCR:

```bash
# Replace YOUR_TOKEN with your actual token
echo "YOUR_TOKEN" | docker login ghcr.io -u sulibot --password-stdin
```

Verify login:

```bash
docker pull ghcr.io/siderolabs/installer:v1.11.5
```

## Step 3: Review Configuration

The configuration is already set up in:

**File:** `terraform/infra/live/cluster-101/custom-installer/terragrunt.hcl`

```hcl
inputs = {
  talos_version = "v1.11.5"  # From versions.hcl

  custom_extensions = [
    "ghcr.io/jsenecal/frr-talos-extension:latest",
  ]

  output_registry = "ghcr.io/sulibot/sol-talos-installer-frr"
}
```

This will create: `ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5`

## Step 4: Build Custom Installer

```bash
cd /Users/sulibot/repos/github/home-ops/terraform/infra/live/cluster-101/custom-installer

# Apply the custom installer module
terragrunt apply
```

**What happens:**
1. Terraform runs `docker run ghcr.io/siderolabs/imager:v1.11.5`
2. Imager builds custom installer with FRR extension
3. Image is loaded into local Docker
4. Image is tagged as `ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5`
5. Image is pushed to GitHub Container Registry
6. Output: `installer_image = "ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5"`

**Expected duration:** 2-5 minutes (downloads base images on first run)

## Step 5: Verify Image in Registry

Check that the image was pushed successfully:

```bash
docker pull ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5
```

Or check on GitHub:
- Go to https://github.com/sulibot?tab=packages
- Look for `sol-talos-installer-frr` package

## Step 6: Update Talos Config to Use Custom Installer

Now we need to update the Talos configuration to use this custom installer instead of the Image Factory installer.

Find where the installer image is referenced. Let me check:

```bash
cd /Users/sulibot/repos/github/home-ops
grep -r "installer.*factory\|install_image" terraform/infra/live/cluster-101/
```

You'll need to update the machine config to reference the custom installer. This is typically in the `talos-config` module.

## Step 7: Add FRR Configuration

Create an ExtensionServiceConfig for FRR. This should be added to your Talos machine configuration:

**Example configuration:**

```yaml
---
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
environment:
  - ASN_LOCAL=4200001001    # Your BGP AS number
  - NODE_IP=10.10.10.10     # Node's /32 IP address
```

The FRR extension requires:
- **ASN_LOCAL**: Local AS number for BGP peering with upstream routers
- **NODE_IP**: The node's /32 IP address (typically on `lo` or `dummy0`)

You'll need to set these per-node or use Talos machine config templating.

## Step 8: Deploy Cluster

After updating the Talos configuration:

```bash
cd /Users/sulibot/repos/github/home-ops/terraform/infra/live/cluster-101

# Review what will change
terragrunt run-all plan

# Apply changes
terragrunt run-all apply
```

## Step 9: Verify FRR Extension

Once nodes are rebuilt/upgraded:

```bash
# Check extensions on a node
talosctl -n 10.0.101.11 get extensions

# Should show:
# - i915
# - intel-ucode
# - qemu-guest-agent
# - util-linux-tools
# - zfs
# - nfsd
# - nfsrahead
# - frr  <-- NEW!
```

Check FRR service:

```bash
talosctl -n 10.0.101.11 services
# Look for 'ext-frr' service

talosctl -n 10.0.101.11 logs ext-frr
# Check FRR logs
```

## Troubleshooting

### Docker not running

```bash
open -a Docker
# Wait 30 seconds for Docker to start
docker info
```

### Registry authentication failed

```bash
# Re-authenticate
echo "YOUR_TOKEN" | docker login ghcr.io -u sulibot --password-stdin
```

### Image build failed

Check the Terraform output for errors. Common issues:
- Docker out of disk space: `docker system prune -a`
- Network timeout: Retry the apply

### Image push failed

- Check token has `write:packages` permission
- Verify you're logged in: `cat ~/.docker/config.json | jq '.auths["ghcr.io"]'`
- Try manual push: `docker push ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5`

### FRR not showing in extensions

- Verify the custom installer was used (check machine config)
- Check node was actually rebuilt (check uptime: `talosctl -n <node> read /proc/uptime`)
- Check installer image in machine config matches custom installer

## Maintenance

### Updating Talos Version

When updating to a new Talos version:

1. Update `terraform/infra/live/common/versions.hcl`:
   ```hcl
   talos_version = "v1.12.0"  # New version
   ```

2. Rebuild custom installer:
   ```bash
   cd terraform/infra/live/cluster-101/custom-installer
   terragrunt apply
   ```

3. This automatically rebuilds with new Talos version and same extensions

### Adding More Extensions

Edit `custom-installer/terragrunt.hcl`:

```hcl
custom_extensions = [
  "ghcr.io/jsenecal/frr-talos-extension:latest",
  "ghcr.io/another/extension:v1.0.0",  # Add more here
]
```

Then `terragrunt apply` to rebuild.

## Next Steps

After completing this guide, you should have:

- ✅ Custom Talos installer with FRR in ghcr.io
- ✅ Terraform module that auto-rebuilds on version changes
- ✅ FRR extension installed on cluster nodes
- ✅ Reproducible, version-controlled infrastructure

You can now configure FRR routing policies using the ExtensionServiceConfig.
