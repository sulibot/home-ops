# Talos FRR Boot Configuration Guide

## Overview

This document explains how to configure FRR (BGP routing daemon) to be running and fully configured when Talos nodes boot from ISO, **before** disk installation occurs. This enables immediate BGP peering with the Proxmox gateway during the boot phase.

## Architecture

### Current State

- Talos boot ISO includes FRR extension but lacks configuration
- FRR configuration is applied POST-installation via `talosctl apply-config`
- ExtensionServiceConfig provides the required FRR config files

### Desired State

- FRR fully configured when node boots from ISO
- BGP sessions establish before disk installation
- No manual configuration steps required

### Host-Network Deployment and Prefix Trust Model

Because the FRR extension and Cilium both run with `hostNetwork: true`, they share the same Linux network namespace. This removes the need for veth namespace juggling or helper scripts and makes it straightforward for Cilium to peer directly with FRR over the existing `veth-cilium/veth-frr` pair.

- **Loopback advertisement** is still gated by the Terragrunt-rendered prefix-lists (`LOOPBACK-self-v4`/`LOOPBACK-self-v6`), which are generated from the per-node loopback IPs (`10.${cluster_id}.254.${suffix}/32` and `fd00:${cluster_id}:fe::${suffix}/128`).
- **Cilium remains the arbiter** of which additional prefixes (LoadBalancer IPs, pod CIDRs, etc.) propagate to FRR. The extension exposes `bgp_cilium_allowed_prefixes` (aka `CILIUM_ALLOWED_PREFIXES` in the ExtensionServiceConfig) so operators can optionally gate what Cilium advertises; when that list is empty, FRR simply forwards everything Cilium sends.
- **No host helper script** is necessary—the extension now configures the shared veth pair directly inside its startup script.

This model keeps FRR transparent; you only need to update Cilium’s advertisements when you want to change what reaches the upstream fabric. The FRR extension just ensures the node loopbacks are advertised early while trusting Cilium for everything else.

## Solution: Hybrid Cloud-Init + Per-Node ISOs

### Approach

Use Talos nocloud platform's cloud-init capability to inject node-specific machine configs (including ExtensionServiceConfig for FRR) via separate CIDATA ISOs. Each node gets:

1. **Base Talos ISO** - Shared across all nodes, contains FRR extension
2. **CIDATA ISO** - Node-specific, contains boot-time machine config with FRR configuration

### Boot Sequence

```
1. Proxmox VM boots with two CD-ROMs:
   - Primary: talos-v1.11.5-nocloud.iso (base Talos)
   - Secondary: solcp01-cidata.iso (node config)

2. Talos detects nocloud platform → reads CIDATA ISO

3. Applies machine config from user-data:
   - Network configuration (IPs, loopback)
   - ExtensionServiceConfig for FRR

4. FRR extension starts with config files:
   - /usr/local/etc/frr/frr.conf (BGP config)
   - /usr/local/etc/frr/daemons (enable bgpd)

5. BGP session establishes with Proxmox gateway

6. Node ready for installation with working routing
```

## Implementation

### Phase 1: Create CIDATA ISO Generation Module

**Location:** `terraform/infra/modules/talos_cidata_iso/`

**Purpose:** Generate nocloud-compatible ISOs with embedded machine configs

**Files to Create:**

#### `main.tf`

```hcl
variable "node_name" {
  description = "Node hostname (e.g., solcp01)"
  type        = string
}

variable "machine_config" {
  description = "Rendered Talos machine config YAML"
  type        = string
}

variable "output_dir" {
  description = "Directory to write ISO"
  type        = string
  default     = "/tmp/talos-cidata"
}

resource "null_resource" "build_cidata_iso" {
  triggers = {
    machine_config_hash = sha256(var.machine_config)
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p /tmp/cidata-${var.node_name}

      # user-data: Full Talos machine config
      cat > /tmp/cidata-${var.node_name}/user-data <<'EOF'
${var.machine_config}
EOF

      # meta-data: Instance ID and hostname
      cat > /tmp/cidata-${var.node_name}/meta-data <<'EOF'
instance-id: ${var.node_name}
local-hostname: ${var.node_name}
EOF

      # network-config: Empty (Talos handles via machine config)
      touch /tmp/cidata-${var.node_name}/network-config

      # Build ISO with cidata label
      mkdir -p ${var.output_dir}
      genisoimage -output ${var.output_dir}/${var.node_name}-cidata.iso \
        -volid cidata -joliet -rock \
        /tmp/cidata-${var.node_name}/

      rm -rf /tmp/cidata-${var.node_name}
    EOT
  }
}

output "iso_path" {
  value = "${var.output_dir}/${var.node_name}-cidata.iso"
}

output "iso_name" {
  value = "${var.node_name}-cidata.iso"
}
```

#### `variables.tf`

```hcl
variable "node_name" {
  description = "Node hostname"
  type        = string
}

variable "machine_config" {
  description = "Rendered Talos machine config YAML"
  type        = string
}

variable "output_dir" {
  description = "Directory to write ISO"
  type        = string
  default     = "/tmp/talos-cidata"
}
```

#### `outputs.tf`

```hcl
output "iso_path" {
  value       = "${var.output_dir}/${var.node_name}-cidata.iso"
  description = "Full path to generated CIDATA ISO"
}

output "iso_name" {
  value       = "${var.node_name}-cidata.iso"
  description = "Filename of generated CIDATA ISO"
}
```

### Phase 2: Modify Talos Config Generation

**File:** `terraform/infra/modules/talos_config/main.tf`

**Add Boot Config Generation:**

```hcl
locals {
  # Boot-time config: Minimal + FRR ExtensionServiceConfig
  boot_machine_configs = {
    for node_name, node in local.all_nodes : node_name => yamlencode({
      version = "v1alpha1"
      machine = {
        type = node.machine_type
        network = {
          hostname = node.hostname
          interfaces = [
            {
              interface = var.bgp_interface  # ens18
              addresses = [
                "${node.public_ipv6}/64",
                "${node.public_ipv4}/24"
              ]
              routes = [
                {
                  network = "::/0"
                  gateway = "fd00:${var.cluster_id}::fffe"  # Anycast gateway
                  metric  = 1024
                }
              ]
            },
            {
              interface = "lo"
              addresses = [
                "fd00:${var.cluster_id}:fe::${node.node_suffix}/128",  # IPv6 loopback
                "10.${var.cluster_id}.254.${node.node_suffix}/32"      # IPv4 loopback
              ]
            }
          ]
        }
      }
    }) + "\n---\n" + templatefile("${path.module}/extension-service-config.yaml.tpl", {
      frr_conf_content = local.frr_configs[node_name]
      hostname         = node.hostname
      enable_bfd       = var.bgp_enable_bfd
    })
  }
}

output "boot_machine_configs" {
  value       = local.boot_machine_configs
  description = "Per-node boot-time machine configs with FRR ExtensionServiceConfig"
}
```

### Phase 3: Integrate CIDATA ISO Build

**File:** `terraform/infra/live/clusters/cluster-101/config/terragrunt.hcl`

**Add After Existing Dependencies:**

```hcl
# Generate CIDATA ISOs for each node with embedded boot configs
module "cidata_isos" {
  source = "../../../../modules/talos_cidata_iso"

  for_each = module.talos_config.boot_machine_configs

  node_name       = each.key
  machine_config  = each.value
  output_dir      = "${get_repo_root()}/build/cidata-isos"
}

# After hook to upload CIDATA ISOs to Proxmox
after_hook "upload_cidata_isos" {
  commands     = ["apply"]
  execute      = ["bash", "-c", <<-EOT
    set -e
    cd ${get_repo_root()}/build/cidata-isos
    for iso in *.iso; do
      echo "Uploading $iso to Proxmox..."
      # Upload command depends on your Proxmox setup
      # Example: scp $iso root@proxmox:/mnt/pve/cephfs/template/iso/
    done
  EOT
  ]
  run_on_error = false
}
```

### Phase 4: Update Proxmox VM Configuration

**VM Provisioning (Terraform or Manual):**

```hcl
resource "proxmox_vm_qemu" "talos_node" {
  # ... existing config ...

  # Boot order: Primary ISO first, then disk
  boot = "order=ide0;scsi0"

  # Base Talos ISO (shared across all nodes)
  cdrom {
    file    = "cephfs:iso/talos-v1.11.5-nocloud.iso"
    slot    = "ide0"
  }

  # Node-specific CIDATA ISO
  cdrom {
    file    = "cephfs:iso/${var.node_name}-cidata.iso"
    slot    = "ide2"
  }

  # ... rest of VM config ...
}
```

## FRR Configuration

### What Gets Embedded

The CIDATA ISO contains **full production FRR configuration**, not a minimal version. This is because:

- BGP requires node-specific ASN, router ID, and IPs to function
- No meaningful "minimal" BGP config exists
- Enables immediate connectivity for installation process

### Configuration Template

Reuses existing `frr.conf.j2` template with per-node variables:

```yaml
hostname: solcp01
router_id: 10.255.101.11
local_asn: 4210101011
node_ipv6: fd00:101::11
cluster_id: 101
gateway_asn: 4200001000
advertise_loopbacks: true
```

### Daemons Enabled

- **zebra** - Routing engine (always enabled)
- **bgpd** - BGP daemon (always enabled)
- **staticd** - Static routes (always enabled)
- **bfdd** - BFD daemon (optional, if BFD enabled)

## Build Process Flow

### Updated Pipeline

```
1. talos_config module
   ├─> Generate boot_machine_configs (minimal + FRR ESC)
   └─> Generate install_machine_configs (full cluster config)

2. talos_images module (unchanged)
   └─> Build base Talos ISO (one-time, shared)

3. talos_cidata_iso module (NEW)
   └─> Generate N CIDATA ISOs (one per node)

4. Upload to Proxmox
   ├─> Base ISO → cephfs:iso/
   └─> CIDATA ISOs → cephfs:iso/

5. Provision VMs
   └─> Attach dual CD-ROMs (base + CIDATA)

6. Boot
   ├─> Talos reads CIDATA user-data
   ├─> Applies ExtensionServiceConfig
   └─> FRR starts with BGP config

7. Install (optional)
   └─> talosctl apply-config with full cluster config
```

## Validation

### After Implementation

1. **Build CIDATA ISOs:**

```bash
cd terraform/infra/live/clusters/cluster-101/config
terragrunt apply
```

2. **Verify ISO Contents:**

```bash
mkdir /tmp/cidata-test
7z x build/cidata-isos/solcp01-cidata.iso -o/tmp/cidata-test
cat /tmp/cidata-test/user-data  # Verify machine config
```

3. **Boot Test VM:**

```bash
# Provision VM with dual CD-ROMs
# Power on VM
```

4. **Check FRR Status:**

```bash
talosctl -n solcp01 service frr status
talosctl -n solcp01 exec -- vtysh -c 'show run'
talosctl -n solcp01 exec -- vtysh -c 'show bgp ipv6 summary'
```

5. **Verify BGP Session:**

```bash
# From Proxmox host:
ssh root@10.10.0.1 "vtysh -c 'show bgp vrf vrf_evpnz1 ipv6 summary'"
# Should show solcp01's session in Established state
```

6. **Test Loopback Reachability:**

```bash
# From Proxmox host:
ping6 fd00:101:fe::11  # Should respond if BGP advertising works
```

## Trade-offs

### Advantages

- ✅ Native Talos nocloud platform support
- ✅ FRR running before disk installation
- ✅ No custom Talos code or patches required
- ✅ Fully automated via Terraform
- ✅ Node-specific configs (ASN, IPs) correctly applied

### Disadvantages

- ⚠️ Multiple ISOs per cluster (6 CIDATA ISOs for 6 nodes)
- ⚠️ Storage overhead: ~600MB total (100MB per CIDATA ISO)
- ⚠️ Build complexity: Two-ISO boot sequence

### Mitigations

- Storage is negligible with Ceph distributed storage
- Build process fully automated via Terraform modules
- Two-ISO sequence is transparent to users (handled by Proxmox)

## Troubleshooting

### FRR Not Starting on Boot

**Check if CIDATA ISO is detected:**

```bash
talosctl -n solcp01 dmesg | grep -i cloud-init
talosctl -n solcp01 dmesg | grep -i cidata
```

**Check if machine config was applied:**

```bash
talosctl -n solcp01 get machineconfig
```

**Check FRR service logs:**

```bash
talosctl -n solcp01 logs frr
```

### BGP Session Not Establishing

**Verify FRR configuration:**

```bash
talosctl -n solcp01 exec -- vtysh -c 'show run'
```

**Check BGP neighbor status:**

```bash
talosctl -n solcp01 exec -- vtysh -c 'show bgp neighbor fd00:101::fffe'
```

**Verify gateway reachability:**

```bash
talosctl -n solcp01 exec -- ping6 fd00:101::fffe
```

### CIDATA ISO Not Mounting

**Verify ISO label:**

```bash
isoinfo -d -i solcp01-cidata.iso | grep "Volume id"
# Should show: Volume id: cidata
```

**Check VM CD-ROM configuration:**

```bash
# Ensure both CD-ROMs attached to VM
# Verify boot order includes both ISOs
```

## Future Migration Path

### Talos v1.12 and Beyond

When Talos v1.12 becomes stable:

- Native support for embedded machine config in ISO
- Can simplify to single-ISO-per-node approach
- Remove CIDATA ISO module
- Current solution migrates cleanly to v1.12 pattern

**Migration Steps:**

1. Upgrade Talos to v1.12
2. Refactor build to use `--embed-config` imager flag
3. Remove CIDATA ISO module
4. Single-ISO-per-node approach

## References

- [Talos NoCloud Platform Documentation](https://www.talos.dev/v1.11/talos-guides/install/cloud-platforms/nocloud/)
- [Talos Extension Services](https://www.talos.dev/v1.9/advanced/extension-services/)
- [Talos System Extensions](https://www.talos.dev/v1.11/talos-guides/configuration/system-extensions/)
- Current FRR config: `terraform/infra/modules/talos_config/frr.conf.j2`
- Extension service template: `terraform/infra/modules/talos_config/extension-service-config.yaml.tpl`

## Related Documentation

- [IP Addressing Layout](./ip-addressing-layout.md)
- [FRR BGP Architecture](./frr-bgp-architecture.md)
- [FRR BGP Design Specification](./frr-bgp-design-specification.md)
