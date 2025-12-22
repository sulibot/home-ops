# Cluster-101 Current State

**Last Updated**: 2025-12-19

## Infrastructure Status

### ✅ Completed Work

1. **Extension Configuration**: All system extensions properly configured with pinned SHA256 digests
   - intel-ucode (20250812)
   - qemu-guest-agent (10.0.2)
   - crun (1.24)
   - ctr (v2.1.5)
   - frr (v1.0.18) - custom extension

2. **Image Building**: Both boot ISO and installer image modules updated
   - Boot ISO: `talos-amd64-v1.11.5.iso` with all 5 extensions
   - Installer: `ghcr.io/sulibot/sol-talos-installer-frr:v1.11.5` with all 5 extensions
   - Both validated with complete extension manifests

3. **Directory Structure**: Refactored for better workflow
   ```
   cluster-101/
   ├── images/          # Build once, update infrequently
   │   ├── 1-talos-install-image-build/
   │   ├── 2-talos-boot-iso-build/
   │   └── 3-boot-iso-upload/
   └── cluster/         # Deploy and manage frequently
       ├── 1-talos-vms-create/
       ├── 2-machine-config-generate/
       └── 3-cluster-bootstrap/
   ```

4. **BGP Configuration**: Proxmox FRR corrected
   - Accepts Talos node ASNs: 4210000000-4210999999
   - Accepts Cilium ASNs: 4220000000-4220999999
   - Combined range: 4210000000-4229999999

5. **Safety Verification**: No staleness issues
   - Terragrunt dependencies ensure fresh state
   - `wipe = false` configured (preserves data during upgrades)
   - Machine configs update via Terraform
   - Extension binaries update via `talosctl upgrade`

### 📝 Configuration Files

#### Extension Definitions
Location: `terraform/infra/live/common/install-schematic.hcl`

All extensions use full OCI image references with SHA256 digests for reproducibility:
```hcl
install_system_extensions = [
  "ghcr.io/siderolabs/intel-ucode:20250812@sha256:31142ac037235e6779eea9f638e6399080a1f09e7c323ffa30b37488004057a5",
  "ghcr.io/siderolabs/qemu-guest-agent:10.0.2@sha256:9720300de00544eca155bc19369dfd7789d39a0e23d72837a7188f199e13dc6c",
  "ghcr.io/siderolabs/crun:1.24@sha256:157f1c563931275443dd46fbc44c854c669f5cf4bbc285356636a57c6d33caed",
  "ghcr.io/siderolabs/ctr:v2.1.5@sha256:73abe655f96bb40a02fc208bf2bed695aa02a85fcd93ff521a78bb92417652c5",
]

custom_system_extensions = [
  "ghcr.io/sulibot/talos-frr-extension:v1.0.18@sha256:b6cd79caf2068ffba94bb69d855a1d6db1d83076a79fa9dc0f68eef6ced9bc44"
]
```

#### Machine Configuration
Location: `terraform/infra/modules/talos_config/main.tf`

Install configuration (lines 74-79, 186-190):
```hcl
install = {
  disk  = var.install_disk
  image = var.installer_image
  wipe  = false  # Safe for upgrades
}
```

BGP/FRR configuration (lines 244-270):
- Local ASN formula: 4210000000 + cluster_id * 1000 + node_suffix
- Router ID: 10.255.{cluster_id}.{node_suffix}
- Peering: Link-local IPv6 unnumbered BGP

### 🚀 Deployment Commands

#### Build Images (Run First or When Extensions/Talos Version Changes)
```bash
cd terraform/infra/live/cluster-101/images
terragrunt run-all apply
```

#### Deploy Cluster (Run After Images Built)
```bash
cd terraform/infra/live/cluster-101/cluster
terragrunt run-all apply
```

#### Update Machine Configs Only (No Extension Changes)
```bash
cd terraform/infra/live/cluster-101/cluster/2-machine-config-generate
terragrunt apply

cd ../3-cluster-bootstrap
terragrunt apply
```

### 🔄 Upgrade Procedures

See [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) for detailed upgrade scenarios:
- Machine config changes (no reboot)
- Extension updates (requires `talosctl upgrade`)
- Talos version upgrades (requires `talosctl upgrade`)

### 🧪 Test Environment

Test VM 9999 exists on pve01:
- Location: vnet101 (fd00:101::99/64)
- Status: Maintenance mode
- Extensions: All 5 validated
- Purpose: Pre-deployment validation
- Note: CA trust issues prevent full config application, but this doesn't affect production deployment

### 📊 Network Configuration

#### VNet 101 (Primary Cluster Network)
- IPv6: fd00:101::/64
- IPv4: 10.0.101.0/24
- Gateway IPv6: fd00:101::ffff (anycast)
- Gateway IPv4: 10.0.101.254
- DNS: fd00:101::fffd, 10.0.101.253

#### Node Loopbacks
- IPv6: fd00:255:101::{node_suffix}/128
- IPv4: 10.255.101.{node_suffix}/32

#### BGP Peering
- Nodes peer with PVE hosts via link-local IPv6
- Anycast gateway: fe80::255:ffff (on all PVE hosts)
- Advertise: Loopback addresses
- Import: Default routes only

### 📋 Node Inventory

#### Control Plane (solcp01, solcp02, solcp03)
- Node suffixes: 11, 12, 13
- ASNs: 4210101011, 4210101012, 4210101013
- Router IDs: 10.255.101.11, 10.255.101.12, 10.255.101.13

#### Workers (solwk01, solwk02, solwk03)
- Node suffixes: 21, 22, 23
- ASNs: 4210101021, 4210101022, 4210101023
- Router IDs: 10.255.101.21, 10.255.101.22, 10.255.101.23

### ⚠️ Important Notes

1. **Never destroy cluster for config-only changes** - Use `terragrunt apply` in cluster/ directories
2. **Always backup before upgrades** - `talosctl etcd snapshot` and Flux export
3. **Extension updates require talosctl** - Machine config apply won't update extension binaries
4. **Wipe=false is intentional** - Enables safe in-place upgrades
5. **Dependencies are critical** - Images must be built before cluster deployment

### 🔗 Related Documentation

- [README.md](./README.md) - Overview and workflow
- [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) - Detailed upgrade procedures
- [BGP_CONFIGURATION.md](../../modules/talos_config/BGP_CONFIGURATION.md) - BGP architecture details

---

## Ready for Deployment

All infrastructure components are configured and validated. The cluster is ready to be deployed using the commands in the "Deployment Commands" section above.
