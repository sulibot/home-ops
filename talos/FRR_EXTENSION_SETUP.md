# FRR Extension Setup for Talos Linux

## Problem

The Talos Image Factory API does **not** support custom/third-party system extensions in schematics. When you try to include `customExtensions` or `security.allow-unsigned-extensions` fields, the API returns:

```
field customExtensions not found in type schematic.Customization
field security not found in type schematic.Customization
```

Image Factory schematics only support official Siderolabs extensions.

## Solution

To use custom extensions like FRR, you must build a custom Talos installer image using the `talos imager` tool.

## Steps

### 1. Build Custom Installer Image

Run the build script:

```bash
cd talos
./build-custom-installer.sh
```

This creates a custom installer in `_out/installer-amd64.tar` that includes:
- Official Siderolabs extensions from the schematic
- FRR extension (`ghcr.io/jsenecal/frr-talos-extension:latest`)

### 2. Push to Container Registry

```bash
# Load the image
docker load < _out/installer-amd64.tar

# Get the image ID from the output
IMAGE_ID=<from-previous-command>

# Tag it
docker tag ${IMAGE_ID} ghcr.io/your-username/talos-installer-frr:v1.11.5

# Push to registry
docker push ghcr.io/your-username/talos-installer-frr:v1.11.5
```

### 3. Configure FRR in Machine Config

Add FRR configuration to your Talos machine config using `ExtensionServiceConfig`:

```yaml
---
apiVersion: v1alpha1
kind: ExtensionServiceConfig
name: frr
environment:
  - ASN_LOCAL=4200001001
  - NODE_IP=10.10.10.10
```

The FRR extension requires:
- **`ASN_LOCAL`**: Local AS Number for BGP peering
- **`NODE_IP`**: The /32 node IP address

### 4. Update Terraform to Use Custom Installer

Modify your Terraform configuration to reference the custom installer image instead of the default Image Factory installer.

Find where your machine config references the installer image and change:

```hcl
# FROM:
installer_image = "factory.talos.dev/installer/${schematic_id}:v1.11.5"

# TO:
installer_image = "ghcr.io/your-username/talos-installer-frr:v1.11.5"
```

### 5. Rebuild Cluster

After updating Terraform:

```bash
cd terraform/infra/live/cluster-101
terragrunt run-all apply
```

## Verification

Once nodes are rebuilt, verify FRR extension is installed:

```bash
talosctl -n <node-ip> get extensions
```

You should see `frr` in the list of extensions.

## References

- [Talos System Extensions Documentation](https://www.talos.dev/v1.11/talos-guides/configuration/system-extensions/)
- [ExtensionServiceConfig](https://www.talos.dev/v1.11/reference/configuration/extensions/extensionserviceconfig/)
- [FRR Talos Extension (abckey)](https://github.com/abckey/frr-talos-extension)
- [How to build a Talos system extension](https://www.siderolabs.com/blog/how-to-build-a-talos-system-extension/)
- [Image Factory Documentation](https://docs.siderolabs.com/talos/v1.11/learn-more/image-factory/)

## Alternative Approach: Local Build without Registry

If you don't want to push to a registry, you can:

1. Build the installer locally
2. Upload it directly to Proxmox as an ISO
3. Use it for installations

However, using a registry is recommended for easier updates and version tracking.
