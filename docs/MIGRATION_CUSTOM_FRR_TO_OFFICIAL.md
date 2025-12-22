# Migration: Custom FRR Extension → Official Siderolabs FRR Extension

**Date**: 2025-12-12
**Status**: In Progress
**Impact**: Requires full cluster rebuild (new installer + schematic)

## Problem

The FRR extension was crash-looping with exit code 1:

```
Missing required configuration: bgp.upstream.local_asn, bgp.upstream.router_id, bgp.cilium.local_asn, bgp.cilium.remote_asn
Config file not found: /etc/frr/config.default.yaml
Config file not found: /usr/local/etc/frr/config.yaml
Config file not found: /usr/local/etc/frr/config.local.yaml
[frr] Configuration validation failed
```

**Root Cause**: Configuration format mismatch

- **Custom Extension** (`ghcr.io/sulibot/frr-talos-extension:latest`): Expects YAML config files
- **Terraform Module**: Now generates native FRR format (`frr.conf`)

The custom FRR extension (v1.0.15) was looking for YAML configuration files that don't exist, because the Terraform configuration was updated to use the native `frr.conf` format expected by the official Siderolabs FRR extension.

## Solution

Migrate to the official Siderolabs FRR extension which:
- Uses native `frr.conf` format (standard FRR configuration)
- Is actively maintained by Siderolabs
- Has better long-term support
- Matches all the documentation we created

## Changes Made

### 1. Updated Install Schematic

**File**: `terraform/infra/live/common/install-schematic.hcl`

**Before**:
```hcl
install_system_extensions = [
  "siderolabs/i915-ucode",
  "siderolabs/qemu-guest-agent",
  "siderolabs/crun",
  "siderolabs/ctr",
]

install_custom_extensions = [
  "ghcr.io/sulibot/frr-talos-extension:latest",  # Custom FRR (YAML config)
]
```

**After**:
```hcl
install_system_extensions = [
  "siderolabs/i915-ucode",
  "siderolabs/qemu-guest-agent",
  "siderolabs/crun",
  "siderolabs/ctr",
  "siderolabs/frr",  # Official FRR extension (native frr.conf)
]

install_custom_extensions = []
```

## Deployment Steps

This migration requires rebuilding the Talos infrastructure from step 1:

### Step 1: Rebuild Custom Installer

The installer must be rebuilt with the official FRR extension.

```bash
cd terraform/infra/live/cluster-101/1-talos-install-image-build
terragrunt destroy -auto-approve  # Remove old custom installer
terragrunt apply -auto-approve    # Build new installer with official FRR

# Expected output:
# output: "ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5"
```

**What This Does**:
- Builds a new Talos installer image
- Includes official `siderolabs/frr` extension
- Pushes to ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5

### Step 2: Regenerate Install Schematic

The schematic defines which extensions are loaded at boot time.

```bash
cd ../2-talos-schematic-generate
terragrunt destroy -auto-approve  # Remove old schematic
terragrunt apply -auto-approve    # Generate new schematic with official FRR

# Expected output:
# schematic_id = "abcdef123456..."  # New schematic ID
```

**What This Does**:
- Generates a new Talos schematic with official FRR extension
- Returns a schematic ID used for factory image

### Step 3: Upload New Boot ISO (Optional)

Only needed if you want to boot new nodes from ISO.

```bash
cd ../3-boot-iso-upload
terragrunt destroy -auto-approve  # Remove old ISO from Proxmox
terragrunt apply -auto-approve    # Upload new ISO with official FRR

# Expected output:
# iso_file_id = "local:iso/talos-amd64-v1.11.5-cluster-101.iso"
```

**What This Does**:
- Downloads ISO from factory.talos.dev using new schematic
- Uploads to Proxmox datastore

### Step 4: Recreate VMs (No Changes Needed)

VMs don't need to be recreated unless you want to boot from new ISO.

```bash
cd ../4-talos-vms-create
terragrunt plan  # Verify no changes

# Expected output:
# No changes. Your infrastructure matches the configuration.
```

**Note**: Existing VMs will be upgraded in-place via machine config in Step 5.

### Step 5: Regenerate Machine Configs

This generates new machine configs with the official FRR extension and native `frr.conf`.

```bash
cd ../5-machine-config-generate
terragrunt apply -auto-approve

# Preview BGP config to verify it's using native frr.conf format
terragrunt output bgp_config_preview

# Expected output:
# ! FRR Configuration for solcp01
# frr version 10.2
# frr defaults datacenter
# hostname solcp01
# ...
# bfd
#  profile normal
#   detect-multiplier 3
# ...
```

**What This Does**:
- Generates machine configs for all nodes
- Includes ExtensionServiceConfig with native `frr.conf`
- Enables BFD and loopback advertisement (as configured)
- Exports configs to talos/clusters/cluster-101/

### Step 6: Apply New Configs to Nodes

Apply the new machine configs to upgrade from custom FRR to official FRR.

```bash
# Apply to control plane nodes (one at a time to maintain quorum)
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/controlplane.yaml --nodes fd00:101::11

# Wait for FRR to start (check with talosctl service ext-frr)
talosctl -n fd00:101::11 service ext-frr

# Repeat for other control plane nodes
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/controlplane.yaml --nodes fd00:101::12
talosctl -n fd00:101::12 service ext-frr

talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/controlplane.yaml --nodes fd00:101::13
talosctl -n fd00:101::13 service ext-frr

# Apply to worker nodes (can do in parallel if desired)
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/worker.yaml --nodes fd00:101::21
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/worker.yaml --nodes fd00:101::22
talosctl apply-config --file /Users/sulibot/repos/github/home-ops/talos/clusters/cluster-101/worker.yaml --nodes fd00:101::23
```

**What This Does**:
- Talos downloads official FRR extension from factory.talos.dev
- Replaces custom FRR extension (v1.0.15) with official extension
- Applies new ExtensionServiceConfig with native frr.conf
- Restarts FRR service with new configuration

### Step 7: Verify FRR is Working

```bash
# Check FRR extension version (should be official, not v1.0.15)
talosctl -n fd00:101::11 get extensions | grep frr

# Expected output:
# runtime     ExtensionStatus   frr    <version>    frr

# Check FRR service status
talosctl -n fd00:101::11 service ext-frr

# Expected output:
# ext-frr    Running

# Check FRR logs (should NOT show YAML config errors)
talosctl -n fd00:101::11 logs ext-frr

# Expected output:
# [frr] Configuration loaded successfully
# [bgpd] Starting BGP daemon
# ...

# Check BGP neighbor status
talosctl -n fd00:101::11 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show bgp summary"

# Expected output:
# Neighbor         V   AS   MsgRcvd   MsgSent   Up/Down   State/PfxRcd
# fe80::%ens18     4   4200001000   ...   ...   00:00:30   2

# Check BFD peers (should show upstream router)
talosctl -n fd00:101::11 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show bfd peers"

# Expected output:
# peer fe80::xxxx interface ens18
#   Status: up
#   Diagnostics: ok

# Check advertised loopbacks
talosctl -n fd00:101::11 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show bgp ipv4 unicast neighbors fe80::%ens18 advertised-routes"

# Expected output:
# Network          Next Hop            Metric LocPrf Weight Path
# *> 10.255.101.11/32  fe80::xxxx              0         32768 i
```

## Verification Checklist

After migration, verify:

- [ ] FRR extension is official Siderolabs version (not v1.0.15)
- [ ] FRR service is running on all nodes
- [ ] No YAML config errors in logs
- [ ] BGP neighbors are established
- [ ] BFD peers are up
- [ ] Loopback addresses are advertised
- [ ] Default routes are received from upstream
- [ ] Pods can reach the internet
- [ ] Kubernetes services are reachable

## Rollback Plan

If the migration fails, you can rollback by:

1. Revert `install-schematic.hcl`:
   ```bash
   git revert <commit-hash>
   ```

2. Rebuild infrastructure:
   ```bash
   cd terraform/infra/live/cluster-101/1-talos-install-image-build
   terragrunt apply -auto-approve
   # ... repeat steps 2-6 above
   ```

3. Apply old machine configs:
   ```bash
   # Use configs from before migration
   talosctl apply-config --file <old-config> --nodes <node>
   ```

## Benefits of Official FRR Extension

1. **Standard Configuration**: Uses native `frr.conf` format
   - Industry-standard FRR configuration
   - Better documentation and community support
   - All our documentation assumes this format

2. **Active Maintenance**: Maintained by Siderolabs
   - Regular updates with Talos releases
   - Bug fixes and security patches
   - Tested with Talos release cycle

3. **Simplified Architecture**: No custom extension builds
   - Factory.talos.dev handles extension delivery
   - No need to maintain custom ghcr.io images
   - Easier to upgrade Talos versions

4. **Better Integration**: Official extension works seamlessly
   - Proper ExtensionServiceConfig support
   - Native frr.conf mounting
   - Standard daemon management

## Configuration Format Comparison

### Custom Extension (YAML)

```yaml
# /usr/local/etc/frr/config.yaml
bgp:
  upstream:
    local_asn: 4210101011
    router_id: 10.255.101.11
    remote_asn: 4200001000
  cilium:
    local_asn: 4220101011
    remote_asn: 4220101011
```

### Official Extension (Native FRR)

```
# /usr/local/etc/frr/frr.conf
frr version 10.2
hostname solcp01
!
bfd
 profile normal
  detect-multiplier 3
  receive-interval 300
  transmit-interval 300
!
router bgp 4210101011
 bgp router-id 10.255.101.11
 neighbor fe80::%ens18 remote-as 4200001000
 neighbor fe80::%ens18 bfd
 !
 address-family ipv4 unicast
  neighbor fe80::%ens18 activate
  neighbor fe80::%ens18 route-map IMPORT-DEFAULT-v4 in
  neighbor fe80::%ens18 route-map ADVERTISE-LOOPBACKS out
 exit-address-family
!
```

## Related Documentation

- [BGP Configuration Guide](../terraform/infra/modules/talos_config/BGP_CONFIGURATION.md)
- [ASN Allocation Scheme](NETWORK_ASN_ALLOCATION.md)
- [FRR Extension README](https://github.com/siderolabs/extensions/tree/main/network/frr)
- [Talos ExtensionServiceConfig](https://www.talos.dev/v1.11/reference/configuration/#extensionserviceconfig)

## Timeline

| Date | Action | Status |
|------|--------|--------|
| 2025-12-12 | Identified custom FRR crash loop (exit code 1) | ✅ Complete |
| 2025-12-12 | Updated install-schematic.hcl to official FRR | ✅ Complete |
| 2025-12-12 | Documented migration plan | ✅ Complete |
| TBD | Rebuild installer (step 1) | ⏳ Pending |
| TBD | Regenerate schematic (step 2) | ⏳ Pending |
| TBD | Upload new ISO (step 3) | ⏳ Pending |
| TBD | Regenerate machine configs (step 5) | ⏳ Pending |
| TBD | Apply to nodes (step 6) | ⏳ Pending |
| TBD | Verify FRR working (step 7) | ⏳ Pending |
