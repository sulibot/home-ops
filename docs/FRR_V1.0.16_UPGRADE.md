# FRR Extension v1.0.16 Upgrade

**Date**: 2025-12-12
**Status**: In Progress
**Impact**: Fixes FRR crash loop, enables native frr.conf workflow

## Problem Solved

The FRR extension (v1.0.15) was crash-looping because:

1. **Mismatch**: Terraform module generated native `frr.conf` format
2. **Extension expected**: YAML configuration files (`config.yaml`)
3. **Result**: Container failed validation looking for missing YAML files

```
Missing required configuration: bgp.upstream.local_asn, bgp.upstream.router_id, bgp.cilium.local_asn, bgp.cilium.remote_asn
Config file not found: /usr/local/etc/frr/config.yaml
[frr] Configuration validation failed
```

## Solution: FRR Extension v1.0.16

Updated the FRR extension to support **both** workflows:

### Primary Workflow (New): Pre-rendered frr.conf
```
Terraform → templatefile(frr.conf.j2) → ExtensionServiceConfig → /usr/local/etc/frr/frr.conf
```

Extension now checks for `/usr/local/etc/frr/frr.conf` and uses it directly if present.

### Fallback Workflow (Legacy): YAML-based
```
YAML config → config_loader.py → JSON → render_template.py → frr.conf
```

Still works for backwards compatibility if no pre-rendered frr.conf is found.

## Changes Made

### 1. FRR Extension Repository

**File**: `docker-start`
- Added check for pre-rendered `/usr/local/etc/frr/frr.conf`
- Skip YAML validation and template rendering if frr.conf exists
- Fall back to YAML workflow for backwards compatibility
- Support ExtensionServiceConfig for daemons and vtysh.conf

**File**: `manifest.yaml`
- Version: v1.0.15 → **v1.0.16**
- Updated description
- Updated author to Sulaiman Ahmad

**Commit**: `e9a1d9f` - "feat(v1.0.16): Support pre-rendered frr.conf via ExtensionServiceConfig"

### 2. Home-Ops Repository

**File**: `terraform/infra/live/common/install-schematic.hcl`
- Changed extension: `ghcr.io/sulibot/frr-talos-extension:latest` → `ghcr.io/sulibot/frr-talos-extension:v1.0.16`
- Added comment explaining v1.0.16+ supports native frr.conf

## Deployment Steps

### Step 1: Build and Push v1.0.16 Image

```bash
cd /Users/sulibot/repos/github/frr-talos-extension
docker build -t ghcr.io/sulibot/frr-talos-extension:v1.0.16 \\
             -t ghcr.io/sulibot/frr-talos-extension:latest .
docker push ghcr.io/sulibot/frr-talos-extension:v1.0.16
docker push ghcr.io/sulibot/frr-talos-extension:latest
```

### Step 2: Rebuild Talos Installer

The installer must include v1.0.16 of the extension.

```bash
cd /Users/sulibot/repos/github/home-ops/terraform/infra/live/cluster-101/1-talos-install-image-build
terragrunt destroy -auto-approve  # Remove old installer
terragrunt apply -auto-approve    # Build new installer with v1.0.16
```

**Expected Output**:
```
installer_image = "ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5"
```

### Step 3: Regenerate Install Schematic

```bash
cd ../2-talos-schematic-generate
terragrunt destroy -auto-approve  # Remove old schematic
terragrunt apply -auto-approve    # Generate new schematic with v1.0.16
```

**Expected Output**:
```
schematic_id = "<new-schematic-id>"
```

### Step 4: (Optional) Upload New Boot ISO

Only needed if you want to boot new nodes from ISO.

```bash
cd ../3-boot-iso-upload
terragrunt destroy -auto-approve
terragrunt apply -auto-approve
```

### Step 5: Regenerate Machine Configs

This regenerates configs with the new extension version.

```bash
cd ../5-machine-config-generate
terragrunt apply -auto-approve

# Preview BGP config to verify it's correct
terragrunt output bgp_config_preview
```

**Expected Output**:
```hcl
bgp_config_preview = {
  "solcp01" = <<-EOT
  ! FRR Configuration for solcp01
  frr version 10.2
  hostname solcp01
  !
  bfd
   profile normal
    detect-multiplier 3
    receive-interval 300
    transmit-interval 300
  ...
  EOT
}
```

### Step 6: Apply to Nodes

Apply new configs one node at a time to minimize downtime:

```bash
# Control plane nodes (one at a time for quorum)
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/controlplane.yaml --nodes fd00:101::11
talosctl -n fd00:101::11 logs ext-frr

# Wait for BGP to establish before next node
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/controlplane.yaml --nodes fd00:101::12
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/controlplane.yaml --nodes fd00:101::13

# Worker nodes (can do in parallel if desired)
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/worker.yaml --nodes fd00:101::21
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/worker.yaml --nodes fd00:101::22
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/worker.yaml --nodes fd00:101::23
```

### Step 7: Verify FRR is Working

```bash
# Check extension version (should be v1.0.16)
talosctl -n fd00:101::11 get extensions | grep frr

# Check FRR service status
talosctl -n fd00:101::11 service ext-frr

# Check logs (should show "Found pre-rendered frr.conf" message)
talosctl -n fd00:101::11 logs ext-frr | grep -A 5 "pre-rendered"

# Expected output:
# [frr] Found pre-rendered frr.conf at /usr/local/etc/frr/frr.conf
# [frr] Using native FRR configuration (skipping YAML config and template rendering)
# [frr] Copied pre-rendered FRR configuration:

# Check BGP neighbor status
talosctl -n fd00:101::11 exec --namespace system --cmd /usr/bin/vtysh -- \\
  vtysh -c "show bgp summary"

# Check BFD peers
talosctl -n fd00:101::11 exec --namespace system --cmd /usr/bin/vtysh -- \\
  vtysh -c "show bfd peers"

# Check advertised loopbacks
talosctl -n fd00:101::11 exec --namespace system --cmd /usr/bin/vtysh -- \\
  vtysh -c "show bgp ipv4 unicast neighbors fe80::%ens18 advertised-routes"
```

## What Changed in docker-start

### Before (v1.0.15)
```bash
# Always used YAML config
log "Loading configuration from files..."
python3 /usr/local/bin/config_loader.py --validate || exit 1
python3 /usr/local/bin/config_loader.py --json > /tmp/config.json
python3 /usr/local/bin/render_template.py ${FRR_TEMPLATE} ${CONFIG_SOURCE} /etc/frr/frr.conf
```

### After (v1.0.16)
```bash
# Check for pre-rendered frr.conf first
if [ -f /usr/local/etc/frr/frr.conf ]; then
    log "Found pre-rendered frr.conf at /usr/local/etc/frr/frr.conf"
    log "Using native FRR configuration (skipping YAML config and template rendering)"
    cp /usr/local/etc/frr/frr.conf /etc/frr/frr.conf
    log "Copied pre-rendered FRR configuration:"
    cat /etc/frr/frr.conf
else
    # Legacy YAML workflow (backwards compatible)
    log "No pre-rendered frr.conf found, using YAML configuration workflow"
    python3 /usr/local/bin/config_loader.py --validate || exit 1
    # ... rest of YAML workflow
fi
```

## Configuration Flow Diagram

### v1.0.16 Workflow

```
┌─────────────────────────────────────────────────────┐
│ Terraform (home-ops)                                 │
│ ┌─────────────────────────────────────────────────┐ │
│ │ templatefile("frr.conf.j2", {                   │ │
│ │   hostname   = "solcp01"                        │ │
│ │   router_id  = "10.255.101.11"                  │ │
│ │   local_asn  = 4210101011                       │ │
│ │   remote_asn = 4200001000                       │ │
│ │   enable_bfd = true                             │ │
│ │   advertise_loopbacks = true                    │ │
│ │ })                                               │ │
│ └─────────────────────────────────────────────────┘ │
│                       │                              │
│                       ▼                              │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Rendered frr.conf (native FRR format)           │ │
│ │ ! FRR Configuration for solcp01                 │ │
│ │ frr version 10.2                                │ │
│ │ hostname solcp01                                │ │
│ │ bfd                                             │ │
│ │  profile normal...                              │ │
│ │ router bgp 4210101011...                        │ │
│ └─────────────────────────────────────────────────┘ │
│                       │                              │
│                       ▼                              │
│ ┌─────────────────────────────────────────────────┐ │
│ │ ExtensionServiceConfig (YAML)                   │ │
│ │ apiVersion: v1alpha1                            │ │
│ │ kind: ExtensionServiceConfig                    │ │
│ │ name: frr                                       │ │
│ │ configFiles:                                    │ │
│ │   - content: | <rendered frr.conf>              │ │
│ │     mountPath: /usr/local/etc/frr/frr.conf      │ │
│ │   - content: <daemons>                          │ │
│ │     mountPath: /usr/local/etc/frr/daemons       │ │
│ └─────────────────────────────────────────────────┘ │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼ talosctl apply-config
┌─────────────────────────────────────────────────────┐
│ Talos Node                                           │
│ ┌─────────────────────────────────────────────────┐ │
│ │ /usr/local/etc/frr/frr.conf (mounted by Talos)  │ │
│ │ ! FRR Configuration for solcp01                 │ │
│ │ frr version 10.2                                │ │
│ │ hostname solcp01                                │ │
│ │ bfd...                                          │ │
│ └─────────────────────────────────────────────────┘ │
│                       │                              │
│                       ▼                              │
│ ┌─────────────────────────────────────────────────┐ │
│ │ FRR Extension Container (v1.0.16)               │ │
│ │ docker-start checks:                            │ │
│ │   if [ -f /usr/local/etc/frr/frr.conf ]; then   │ │
│ │     cp to /etc/frr/frr.conf ✓                   │ │
│ │   else                                          │ │
│ │     Use YAML workflow (legacy)                  │ │
│ └─────────────────────────────────────────────────┘ │
│                       │                              │
│                       ▼                              │
│ ┌─────────────────────────────────────────────────┐ │
│ │ FRR Daemons (zebra, bgpd, bfdd, staticd)        │ │
│ │ Read /etc/frr/frr.conf                          │ │
│ │ Establish BGP sessions                          │ │
│ │ Enable BFD                                      │ │
│ │ Advertise loopbacks                             │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## Benefits

1. **No more crash loops** - Extension accepts pre-rendered frr.conf
2. **Simpler workflow** - No YAML conversion needed
3. **Faster iteration** - Edit template, apply config (no image rebuild)
4. **Better visibility** - See actual FRR config in Terraform outputs
5. **Backwards compatible** - Old YAML workflow still works

## Related Documentation

- [BGP Configuration Guide](../terraform/infra/modules/talos_config/BGP_CONFIGURATION.md)
- [ASN Allocation Scheme](NETWORK_ASN_ALLOCATION.md)
- [FRR Extension README](https://github.com/sulibot/frr-talos-extension/blob/master/README.md)
- [FRR Extension Quick Start](https://github.com/sulibot/frr-talos-extension/blob/master/QUICKSTART.md)
