# Network ASN Allocation Scheme

This document describes the BGP Autonomous System Number (ASN) allocation scheme used across the home-ops infrastructure.

## ASN Allocation Formula

All node ASNs are calculated using the following formula:

```
Node ASN = bgp_asn_base + (cluster_id × 1000) + node_suffix
```

### Current Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| `bgp_asn_base` | `4210000000` | Base ASN (RFC 6996 private range) |
| Upstream ASN | `4200001000` | PVE FRR router ASN |

### ASN Ranges by Cluster

Each cluster gets a 1000-ASN block:

| Cluster | Cluster ID | ASN Range | Purpose |
|---------|-----------|-----------|---------|
| **sol** | 101 | 4210101000 - 4210101999 | Production cluster |
| Reserved | 102 | 4210102000 - 4210102999 | Future cluster |
| Reserved | 103 | 4210103000 - 4210103999 | Future cluster |

### Node Suffix Convention

Node suffixes determine the last digits of the ASN:

| Node Type | Suffix Range | Example Hostnames | Example ASNs |
|-----------|--------------|-------------------|--------------|
| **Control Plane** | 11-19 | solcp01, solcp02, solcp03 | 4210101011, 4210101012, 4210101013 |
| **Workers** | 21-99 | solwk01, solwk02, solwk03 | 4210101021, 4210101022, 4210101023 |

## Cluster 101 (sol) - Current Allocations

### Control Plane Nodes

| Hostname | IPv4 Loopback | IPv6 Loopback | Node Suffix | BGP ASN | Router ID |
|----------|---------------|---------------|-------------|---------|-----------|
| solcp01 | 10.255.101.11 | fd00:255:101::11 | 11 | **4210101011** | 10.255.101.11 |
| solcp02 | 10.255.101.12 | fd00:255:101::12 | 12 | **4210101012** | 10.255.101.12 |
| solcp03 | 10.255.101.13 | fd00:255:101::13 | 13 | **4210101013** | 10.255.101.13 |

### Worker Nodes

| Hostname | IPv4 Loopback | IPv6 Loopback | Node Suffix | BGP ASN | Router ID |
|----------|---------------|---------------|-------------|---------|-----------|
| solwk01 | 10.255.101.21 | fd00:255:101::21 | 21 | **4210101021** | 10.255.101.21 |
| solwk02 | 10.255.101.22 | fd00:255:101::22 | 22 | **4210101022** | 10.255.101.22 |
| solwk03 | 10.255.101.23 | fd00:255:101::23 | 23 | **4210101023** | 10.255.101.23 |

### Cilium BGP (Reserved)

Cilium uses a separate ASN offset of +10000000 from the node ASN:

| Node | Node ASN | Cilium ASN | Purpose |
|------|----------|------------|---------|
| solcp01 | 4210101011 | 4220101011 | Cilium BGP Control Plane |
| solcp02 | 4210101012 | 4220101012 | Cilium BGP Control Plane |
| solcp03 | 4210101013 | 4220101013 | Cilium BGP Control Plane |
| solwk01 | 4210101021 | 4220101021 | Cilium BGP Control Plane |
| solwk02 | 4210101022 | 4220101022 | Cilium BGP Control Plane |
| solwk03 | 4210101023 | 4220101023 | Cilium BGP Control Plane |

## BGP Peering Architecture

### Upstream Peering

All Talos nodes peer with the PVE FRR router via link-local IPv6:

```
┌─────────────────────────────────────────────────────────┐
│ PVE FRR (pve01.sulibot.com)                            │
│ ASN: 4200001000                                         │
│ Interface: vmbr0.101 (fe80::xxxx)                      │
└──────────────────┬──────────────────────────────────────┘
                   │
                   │ Link-Local IPv6 BGP (RFC 5549)
                   │ Extended Next-Hop for IPv4 routes
                   │
       ┌───────────┼───────────┬───────────┬──────────────┐
       │           │           │           │              │
   ┌───▼───┐   ┌──▼────┐  ┌──▼────┐  ┌──▼────┐      ┌──▼────┐
   │solcp01│   │solcp02│  │solcp03│  │solwk01│ ...  │solwk03│
   │4210101│   │4210101│  │4210101│  │4210101│      │4210101│
   │   011 │   │   012 │  │   013 │  │   021 │      │   023 │
   └───────┘   └───────┘  └───────┘  └───────┘      └───────┘
```

### BGP Features Enabled

| Feature | Status | Configuration | Purpose |
|---------|--------|---------------|---------|
| **BFD** | ✅ Enabled | detect-multiplier: 3<br>receive-interval: 300ms<br>transmit-interval: 300ms | Fast failover detection (~900ms) |
| **Loopback Advertisement** | ✅ Enabled | IPv4: 10.255.101.0/24 ge 32<br>IPv6: fd00:255:101::/48 ge 128 | External access to nodes |
| **Default Route Import** | ✅ Enabled | Prefix lists for ::/0 and 0.0.0.0/0 | Internet access for pods |
| **IPv4 over IPv6** | ✅ Enabled | Extended Next-Hop (RFC 5549) | IPv4 routes via link-local IPv6 |

## Configuration Files

The ASN allocation is managed through Terraform variables:

- **Module Variables**: `terraform/infra/modules/talos_config/variables.tf`
  - `bgp_asn_base = 4210000000`
  - `bgp_remote_asn = 4200001000`
  - `bgp_interface = "ens18"`
  - `bgp_enable_bfd = false` (default)
  - `bgp_advertise_loopbacks = false` (default)

- **Cluster Configuration**: `terraform/infra/live/cluster-101/5-machine-config-generate/terragrunt.hcl`
  - `bgp_enable_bfd = true` (cluster-specific override)
  - `bgp_advertise_loopbacks = true` (cluster-specific override)

- **FRR Template**: `terraform/infra/modules/talos_config/frr.conf.j2`
  - Native FRR configuration with conditional features
  - Renders per-node configs with calculated ASNs

## Verification Commands

### Check BGP ASN Assignments

```bash
cd terraform/infra/live/cluster-101/5-machine-config-generate
terragrunt output bgp_asn_assignments
```

Expected output:
```hcl
{
  "solcp01" = {
    "local_asn" = 4210101011
    "remote_asn" = 4200001000
    "router_id" = "10.255.101.11"
  }
  # ... more nodes
}
```

### Preview Rendered FRR Configurations

```bash
terragrunt output bgp_config_preview
```

### Check BGP Session Status (on node)

```bash
# BGP summary
talosctl -n solcp01 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show bgp summary"

# BFD peers
talosctl -n solcp01 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show bfd peers"

# Advertised routes
talosctl -n solcp01 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show bgp ipv4 unicast neighbors fe80::%ens18 advertised-routes"

# Received routes
talosctl -n solcp01 exec --namespace system --cmd /usr/bin/vtysh -- \
  vtysh -c "show bgp ipv4 unicast neighbors fe80::%ens18 routes"
```

### Check Node Labels (Kubernetes)

```bash
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
BGP_FRR_ASN:.metadata.labels.bgp\.frr\.asn,\
BGP_CILIUM_ASN:.metadata.labels.bgp\.cilium\.asn
```

Expected output:
```
NAME      BGP_FRR_ASN   BGP_CILIUM_ASN
solcp01   4210101011    4220101011
solcp02   4210101012    4220101012
solcp03   4210101013    4220101013
solwk01   4210101021    4220101021
solwk02   4210101022    4220101022
solwk03   4210101023    4220101023
```

## Adding New Nodes

When adding new nodes to cluster 101:

1. Choose an unused suffix in the appropriate range:
   - Control plane: 14-19
   - Workers: 24-99

2. Example: Adding solwk04
   ```hcl
   # Suffix: 24
   # ASN will be: 4210000000 + (101 × 1000) + 24 = 4210101024
   # IPv4 loopback: 10.255.101.24
   # IPv6 loopback: fd00:255:101::24
   # Router ID: 10.255.101.24
   ```

3. The Terraform module will automatically calculate the ASN and render the FRR config.

## Adding New Clusters

When deploying a new cluster:

1. Choose an unused cluster_id (e.g., 102 for next cluster)

2. ASN range will be: `4210102000 - 4210102999`

3. Update cluster's `terragrunt.hcl`:
   ```hcl
   inputs = {
     cluster_id = 102
     # ... other inputs ...

     # Optional: Override BGP settings
     bgp_remote_asn = 4200001000  # Or different upstream
     bgp_enable_bfd = true
     bgp_advertise_loopbacks = true
   }
   ```

4. Document the new cluster allocation in this file.

## ASN Range Capacity

| Component | Count | Range Used | Remaining |
|-----------|-------|------------|-----------|
| **Per Cluster** | 1000 ASNs | 0-999 | - |
| **Control Plane** | ~10 nodes | 11-19 | Supports 9 CPs |
| **Workers** | ~80 nodes | 21-99 | Supports 79 workers |
| **Reserved/Special** | - | 01-10, 100-999 | Future use |

## References

- **RFC 6996**: Autonomous System (AS) Reservation for Private Use
  - Range: 4200000000 - 4294967295
  - Our base: 4210000000

- **RFC 5549**: Advertising IPv4 Network Layer Reachability Information with an IPv6 Next Hop
  - Enables IPv4 routing over link-local IPv6 BGP sessions

- **BGP Configuration Guide**: [terraform/infra/modules/talos_config/BGP_CONFIGURATION.md](../terraform/infra/modules/talos_config/BGP_CONFIGURATION.md)

## Change Log

| Date | Change | Reason |
|------|--------|--------|
| 2025-12-12 | Initial ASN allocation scheme documented | Established base ASN 4210000000, cluster 101 allocated 4210101000-4210101999 |
| 2025-12-12 | Enabled BFD for cluster 101 | Fast failover detection (~900ms) |
| 2025-12-12 | Enabled loopback advertisement for cluster 101 | Enable external access to nodes for monitoring/management |
