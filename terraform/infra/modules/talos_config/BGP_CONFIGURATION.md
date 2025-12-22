# BGP Configuration Variables

This module supports extensive BGP configuration through Terraform variables, allowing you to customize routing behavior without modifying templates.

## Quick Start

Basic usage with defaults (suitable for most deployments):

```hcl
module "talos_config" {
  source = "../../modules/talos_config"

  # Required variables
  cluster_name     = "sol"
  cluster_id       = 101
  cluster_endpoint = "https://[fd00:101::10]:6443"
  # ... other required vars ...

  # BGP uses sensible defaults - no additional config needed!
  # Default: Peer with ASN 4200001000, no BFD, no loopback advertisement
}
```

## Available BGP Variables

### `bgp_asn_base`

**Description:** Base ASN for node BGP routing
**Type:** `number`
**Default:** `4210000000`
**Validation:** Must be valid private or public ASN (64512-4294967295)

**Formula:** Final node ASN = `bgp_asn_base + (cluster_id × 1000) + node_suffix`

**Examples:**
```hcl
# Use RFC 6996 private ASN range (4200000000-4294967295)
bgp_asn_base = 4210000000  # Default

# Use legacy private ASN range (64512-65535)
bgp_asn_base = 64512

# Use public ASN (if you have one allocated)
bgp_asn_base = 65000
```

**ASN Assignment Example (cluster_id=101):**
| Node | Suffix | Calculated ASN |
|------|--------|----------------|
| solcp01 | 11 | 4210000000 + (101 × 1000) + 11 = **4210101011** |
| solcp02 | 12 | 4210000000 + (101 × 1000) + 12 = **4210101012** |
| solwk01 | 21 | 4210000000 + (101 × 1000) + 21 = **4210101021** |

### `bgp_remote_asn`

**Description:** Upstream router BGP ASN (e.g., your ToR switch, PVE FRR)
**Type:** `number`
**Default:** `4200001000`
**Validation:** Must be between 1 and 4294967295

**Example:**
```hcl
# PVE FRR ASN
bgp_remote_asn = 4200001000  # Default

# Commercial ISP
bgp_remote_asn = 174  # Cogent

# Private network router
bgp_remote_asn = 65000
```

### `bgp_interface`

**Description:** Network interface for BGP peering with upstream router
**Type:** `string`
**Default:** `"ens18"`

**Example:**
```hcl
# Most common (Proxmox VMs)
bgp_interface = "ens18"  # Default

# Bare metal with multiple NICs
bgp_interface = "eth0"

# Bond interface
bgp_interface = "bond0"
```

### `bgp_enable_bfd`

**Description:** Enable BFD (Bidirectional Forwarding Detection) for fast BGP failover
**Type:** `bool`
**Default:** `false`

**When to Enable:**
- ✅ Mission-critical workloads requiring fast failover (<1 second)
- ✅ Multi-homed setups with redundant uplinks
- ✅ Active-active load balancing scenarios

**When to Disable:**
- ❌ Single uplink (no benefit)
- ❌ WAN links with high latency/jitter (false positives)
- ❌ Learning/testing environments

**Example:**
```hcl
bgp_enable_bfd = true

# BFD settings are preconfigured:
# - detect_multiplier: 3
# - receive_interval: 300ms
# - transmit_interval: 300ms
# - Detection time: ~900ms
```

**Verification:**
```bash
talosctl -n node01 exec --namespace system --cmd /usr/bin/vtysh -- vtysh -c "show bfd peers"
```

### `bgp_advertise_loopbacks`

**Description:** Advertise node loopback addresses via BGP
**Type:** `bool`
**Default:** `false`

**When to Enable:**
- ✅ External services need to reach nodes directly (not via LoadBalancer)
- ✅ Multi-cluster setups requiring pod-to-pod communication
- ✅ Monitoring systems outside the cluster
- ✅ Direct SSH access from external networks

**When to Disable:**
- ❌ Nodes should only be reachable via Kubernetes services
- ❌ Security policy requires all external traffic via ingress
- ❌ You only need default route (internet access)

**What Gets Advertised:**
- IPv4: `10.255.<cluster_id>.0/24` with `/32` loopbacks
- IPv6: `fd00:255:<cluster_id>::/48` with `/128` loopbacks

**Example:**
```hcl
bgp_advertise_loopbacks = true

# Advertises:
# - 10.255.101.11/32 (solcp01)
# - 10.255.101.12/32 (solcp02)
# - fd00:255:101::11/128 (solcp01)
# - fd00:255:101::12/128 (solcp02)
```

**Verification:**
```bash
# Check what routes are being advertised
talosctl -n node01 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show ip bgp neighbors <neighbor> advertised-routes"
```

## Complete Configuration Examples

### Example 1: Production Setup with BFD and Loopback Advertisement

```hcl
module "talos_config" {
  source = "../../modules/talos_config"

  cluster_name     = "prod"
  cluster_id       = 100
  cluster_endpoint = "https://[fd00:100::10]:6443"

  # BGP Configuration
  bgp_asn_base             = 4210000000
  bgp_remote_asn           = 65000
  bgp_interface            = "ens18"
  bgp_enable_bfd           = true   # Fast failover
  bgp_advertise_loopbacks  = true   # External monitoring access

  # ... other required variables ...
}
```

**Result:** Each node peers with ASN 65000, uses BFD for sub-second failover, and advertises its loopback IP.

### Example 2: Simple Home Lab (Minimal Config)

```hcl
module "talos_config" {
  source = "../../modules/talos_config"

  cluster_name     = "homelab"
  cluster_id       = 200
  cluster_endpoint = "https://[fd00:200::10]:6443"

  # BGP uses all defaults - no additional config needed!
  # Peers with ASN 4200001000, no BFD, no loopback advertisement

  # ... other required variables ...
}
```

**Result:** Each node gets ASN 4210200000+suffix, peers with default ASN 4200001000.

### Example 3: Multi-Cluster with Different Upstream Routers

```hcl
# Cluster 101: PVE datacenter
module "cluster_101" {
  source           = "../../modules/talos_config"
  cluster_id       = 101
  bgp_remote_asn   = 4200001000  # PVE FRR
  bgp_interface    = "ens18"
  # ...
}

# Cluster 102: Edge location
module "cluster_102" {
  source           = "../../modules/talos_config"
  cluster_id       = 102
  bgp_remote_asn   = 65000      # Different upstream
  bgp_interface    = "eth0"
  # ...
}
```

### Example 4: Using Legacy Private ASN Range

```hcl
module "talos_config" {
  source = "../../modules/talos_config"

  cluster_id       = 1
  bgp_asn_base     = 64512   # Legacy private ASN range
  bgp_remote_asn   = 64500

  # Node ASNs will be:
  # solcp01: 64512 + (1 × 1000) + 11 = 65523
  # solcp02: 64512 + (1 × 1000) + 12 = 65524
  # WARNING: May exceed 65535 with high cluster_id or node_suffix!

  # ... other variables ...
}
```

## Debugging

### View BGP ASN Assignments

```bash
cd terraform/cluster-101/5-machine-config-generate
terragrunt output bgp_asn_assignments
```

Output:
```
bgp_asn_assignments = {
  "solcp01" = {
    "local_asn" = 4210101011
    "remote_asn" = 4200001000
    "router_id" = "10.255.101.11"
  }
  # ...
}
```

### Preview Rendered FRR Configuration

```bash
terragrunt output bgp_config_preview
```

Output shows first 800 characters of each node's `frr.conf`:
```
bgp_config_preview = {
  "solcp01" = <<-EOT
  ! FRR Configuration for solcp01
  ! BGP peering with upstream router via link-local IPv6
  ...
  EOT
}
```

### View Full FRR Config

```bash
terragrunt output -json | jq -r '.bgp_config_preview.value.solcp01'
```

## Migration Guide

### From Hardcoded ASNs to Variables

**Before:**
```hcl
# ASNs were hardcoded in template
local_asn = 4210000000 + (var.cluster_id * 1000) + node.node_suffix
remote_asn = 4200001000
```

**After:**
```hcl
# Use variables (defaults match previous behavior)
bgp_asn_base   = 4210000000  # Default, can omit
bgp_remote_asn = 4200001000  # Default, can omit

# Or customize:
bgp_asn_base   = 65000
bgp_remote_asn = 64500
```

**No Breaking Changes:** If you don't set these variables, behavior is identical to before.

### Enabling BFD on Existing Cluster

1. Update your cluster's `terragrunt.hcl`:
   ```hcl
   inputs = {
     # ... existing vars ...
     bgp_enable_bfd = true
   }
   ```

2. Regenerate configs:
   ```bash
   terragrunt apply
   ```

3. Apply to nodes (one at a time to avoid downtime):
   ```bash
   talosctl apply-config --file outputs/solcp01.yaml --nodes solcp01
   # Wait for BGP to re-establish
   talosctl apply-config --file outputs/solcp02.yaml --nodes solcp02
   # ...
   ```

4. Verify BFD:
   ```bash
   talosctl -n solcp01 exec --namespace system --cmd /usr/bin/vtysh -- \
     vtysh -c "show bfd peers"
   ```

## Best Practices

1. **ASN Selection:**
   - Use RFC 6996 range (4200000000-4294967295) for new deployments
   - Reserve ASN blocks per cluster: cluster 100 = 4210100000-4210100999
   - Document ASN assignments in your infrastructure repo

2. **BFD:**
   - Only enable if you have redundant uplinks
   - Test failover behavior in non-production first
   - Monitor for BFD flapping (indicates network issues)

3. **Loopback Advertisement:**
   - Enable only if external systems need direct node access
   - Use firewall rules to restrict access to advertised loopbacks
   - Consider advertising only control plane nodes

4. **Testing:**
   - Always run `terragrunt plan` before apply
   - Check `bgp_asn_assignments` output for correctness
   - Preview rendered configs with `bgp_config_preview`

## Troubleshooting

### ASN Validation Error

```
Error: BGP ASN must be a valid private ASN
```

**Cause:** ASN outside valid range (64512-4294967295)

**Fix:** Use RFC 6996 range:
```hcl
bgp_asn_base = 4210000000
```

### BGP Neighbor Not Establishing After BFD Enable

**Cause:** Upstream router doesn't support BFD or has different BFD settings

**Fix:** Check upstream router BFD config:
```bash
# On PVE FRR
vtysh -c "show running-config" | grep -A5 bfd
```

Ensure settings match:
- detect-multiplier: 3
- receive-interval: 300
- transmit-interval: 300

### Loopbacks Not Being Advertised

**Cause:** `bgp_advertise_loopbacks = false` (default)

**Fix:** Enable in your `terragrunt.hcl`:
```hcl
inputs = {
  bgp_advertise_loopbacks = true
}
```

Then verify route-map is applied:
```bash
talosctl -n node01 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show running-config" | grep -A10 "ADVERTISE-LOOPBACKS"
```
