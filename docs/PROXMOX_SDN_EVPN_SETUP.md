# Proxmox SDN with EVPN Setup

## Overview

This document describes the Proxmox Software-Defined Networking (SDN) implementation using EVPN (Ethernet VPN) with FRR (Free Range Routing) as the control plane.

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Proxmox Cluster (3 nodes)                 │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐          │
│  │  pve01   │◄────►│  pve02   │◄────►│  pve03   │          │
│  │          │      │          │      │          │          │
│  │ FRR BGP  │      │ FRR BGP  │      │ FRR BGP  │          │
│  │ AS 4.2B  │      │ AS 4.2B  │      │ AS 4.2B  │          │
│  └────┬─────┘      └────┬─────┘      └────┬─────┘          │
│       │ iBGP EVPN       │ iBGP EVPN       │                │
│       │ (25G Mesh)      │ (25G Mesh)      │                │
│       └─────────────────┴─────────────────┘                │
│                                                               │
├─────────────────────────────────────────────────────────────┤
│                      VXLAN Overlays                          │
├─────────────────────────────────────────────────────────────┤
│  VNet 100: General Workloads    (VXLAN 10100)               │
│  VNet 101: Talos Cluster 101    (VXLAN 10101)               │
│  VNet 102: Talos Cluster 102    (VXLAN 10102)               │
│  VNet 103: Talos Cluster 103    (VXLAN 10103)               │
│  VRF:      Layer 3 Routing      (VXLAN 4096)                │
└─────────────────────────────────────────────────────────────┘
```

### Key Features

1. **EVPN Control Plane**: BGP EVPN for MAC/IP distribution and BUM traffic handling
2. **VXLAN Data Plane**: Layer 2 overlay network with automatic tunnel creation
3. **VRF for L3 Routing**: Shared routing domain for inter-VNet communication
4. **Distributed Gateways**: Anycast gateway (SVI) on each PVE host for local routing
5. **Exit Nodes**: All PVE hosts act as SNAT exit points for internet access
6. **Route Import**: Import default route from RouterOS (RT 65000:1)

### Network Details

| Component | Value |
|-----------|-------|
| EVPN Zone ID | evpnz1 |
| VRF VXLAN ID | 4096 |
| MTU | 1450 (1500 - 50 byte VXLAN overhead) |
| BGP ASN | 4200001000 |
| Controller Type | FRR (distributed on each PVE host) |

### VNet Configuration

| VNet ID | Alias | VXLAN ID | IPv6 Subnet | Gateway |
|---------|-------|----------|-------------|---------|
| vnet100 | General Workloads | 10100 | fd00:100::/64 | fd00:100::1 |
| vnet101 | Talos Cluster 101 | 10101 | fd00:101::/64 | fd00:101::1 |
| vnet102 | Talos Cluster 102 | 10102 | fd00:102::/64 | fd00:102::1 |
| vnet103 | Talos Cluster 103 | 10103 | fd00:103::/64 | fd00:103::1 |

## Deployment

### Prerequisites

1. **FRR Installed**: FRR must be running on all PVE hosts
2. **BGP iBGP Mesh**: BGP sessions established between all PVE nodes
3. **Network Connectivity**: 25G mesh network (enp1s0f0np0, enp1s0f1np1)
4. **Loopback Addresses**: Infrastructure loopbacks configured (fd00:255::1-3)

### Step 1: Configure FRR for EVPN

The FRR configuration is managed via Ansible. The L2VPN EVPN address-family is added to the BGP configuration.

**File**: `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

```jinja2
router bgp {{ PVE_ASN }}
  bgp router-id 10.0.10.{{ PVE_ID }}
  no bgp default ipv4-unicast

  # ... existing IPv4/IPv6 address-families ...

  ! L2VPN EVPN for Proxmox SDN
  address-family l2vpn evpn
    neighbor enp1s0f0np0 activate
    neighbor enp1s0f1np1 activate
    advertise-all-vni
    advertise-svi-ip
  exit-address-family
exit
```

Apply with Ansible:
```bash
cd ansible/lae.proxmox
ansible-playbook -i inventory/hosts.ini playbooks/stage2-configure-frr.yml
```

### Step 2: Create FRR SDN Controller

The EVPN controller must be created manually via CLI before Terraform can manage the zone/vnets:

```bash
ssh root@pve01.sulibot.com \
  'pvesh create /cluster/sdn/controllers \
    --controller frr \
    --type evpn \
    --asn 4200001000 \
    --peers "fd00:255::1,fd00:255::2,fd00:255::3"'
```

### Step 3: Deploy SDN Infrastructure via Terraform

The SDN infrastructure is managed by Terraform/Terragrunt.

**Module Location**: `terraform/infra/modules/proxmox_sdn/`
**Live Config**: `terraform/infra/live/common/0-sdn-setup/`

Initialize and apply:
```bash
cd terraform/infra/live/common/0-sdn-setup
terragrunt init
terragrunt apply
```

This creates:
- EVPN zone (evpnz1)
- 4 VNets (vnet100-103)
- Subnets with gateway addresses
- Applies the SDN configuration cluster-wide

## Verification

### Check VXLAN Interfaces

```bash
ssh root@pve01.sulibot.com 'ip -d link show type vxlan'
```

Expected output:
- `vxlan_vnet100` (VXLAN ID 10100)
- `vxlan_vnet101` (VXLAN ID 10101)
- `vxlan_vnet102` (VXLAN ID 10102)
- `vxlan_vnet103` (VXLAN ID 10103)
- `vrfvx_evpnz1` (VRF VXLAN ID 4096)

### Check BGP EVPN Routes

```bash
ssh root@pve01.sulibot.com 'vtysh -c "show bgp l2vpn evpn route"'
```

Look for:
- **Type-2 routes**: MAC/IP advertisements for gateway SVIs
- **Type-3 routes**: IMET (Inclusive Multicast Ethernet Tag) for BUM traffic
- Routes from other PVE nodes (indicates EVPN peering is working)

### Check BGP EVPN Neighbors

```bash
ssh root@pve01.sulibot.com 'vtysh -c "show bgp l2vpn evpn summary"'
```

Should show 2 neighbors (mesh links) in Established state.

### Check VNet Configuration

```bash
ssh root@pve01.sulibot.com 'pvesh get /cluster/sdn/vnets'
```

### Check SDN Status

```bash
ssh root@pve01.sulibot.com 'pvesh get /cluster/sdn/vnets/vnet101'
```

## Using SDN for VMs

### Attaching VMs to VNets

To use SDN for a VM (e.g., Talos cluster-101), update the cluster configuration:

**File**: `terraform/infra/live/cluster-101/cluster.hcl`

```hcl
network = {
  bridge_public = "vmbr0"      # Legacy: used when use_sdn = false
  vlan_public   = 101          # Legacy: used when use_sdn = false
  bridge_mesh   = "vnet101"    # Can also be SDN VNet
  vlan_mesh     = 0
  public_mtu    = 1500         # Legacy: used when use_sdn = false
  mesh_mtu      = 8930
  use_sdn       = true         # Enable SDN VNet for public interface
}
```

When `use_sdn = true`:
- Public interface (net0/ens18) connects to SDN VNet (vnet101)
- No VLAN tag needed (VXLAN handles segmentation)
- MTU automatically set to 1450
- VM gets IPv6 address from VNet subnet (fd00:101::/64)
- Default gateway is VNet gateway (fd00:101::1)

### VM Recreation Required

**Important**: Changing the network bridge requires VM recreation. The Terraform module will destroy and recreate VMs when switching from VLAN to SDN.

## Troubleshooting

### EVPN Routes Not Appearing

1. Check BGP EVPN neighbors:
   ```bash
   vtysh -c "show bgp l2vpn evpn summary"
   ```

2. Verify FRR configuration:
   ```bash
   vtysh -c "show running-config"
   ```

3. Check for BGP errors:
   ```bash
   vtysh -c "show bgp l2vpn evpn neighbors"
   ```

### VXLAN Tunnels Not Creating

1. Verify SDN controller:
   ```bash
   pvesh get /cluster/sdn/controllers/frr
   ```

2. Check SDN reload status:
   ```bash
   pvesh set /cluster/sdn
   ```

3. Verify VXLAN interfaces:
   ```bash
   ip -d link show type vxlan
   ```

### VM Connectivity Issues

1. Check if VM is on correct VNet:
   ```bash
   qm config <VMID> | grep net
   ```

2. Verify VNet gateway is reachable from VM:
   ```bash
   # From inside VM
   ping6 fd00:101::1
   ```

3. Check EVPN MAC/IP routes:
   ```bash
   vtysh -c "show bgp l2vpn evpn route type 2"
   ```

### MTU Issues

VXLAN adds 50 bytes of overhead. Ensure:
- VNet MTU = 1450
- VM interface MTU ≤ 1450
- Applications tolerate reduced MTU

## Migration from VLAN to SDN

### Pre-Migration Checklist

- [ ] FRR EVPN configured and verified
- [ ] SDN infrastructure deployed and tested
- [ ] Backup VM configurations
- [ ] Plan maintenance window (VMs will be recreated)
- [ ] Test with non-critical VMs first

### Migration Steps

1. **Enable SDN in cluster config**:
   ```hcl
   use_sdn = true
   ```

2. **Plan the Terraform changes**:
   ```bash
   cd terraform/infra/live/cluster-101/4-talos-vms-create
   terragrunt plan
   ```
   Review the changes - VMs will be destroyed and recreated.

3. **Apply the changes**:
   ```bash
   terragrunt apply
   ```
   VMs will be recreated with SDN VNet attachments.

4. **Verify connectivity**:
   - VMs get IPv6 addresses from VNet subnet
   - Can ping VNet gateway
   - Can reach internet via exit nodes
   - Inter-VM communication works

### Rollback

To rollback to VLAN-based networking:
```hcl
use_sdn = false
```

Run `terragrunt apply` to recreate VMs with VLAN configuration.

## Benefits

1. **VM Mobility**: VMs can live-migrate between PVE hosts without reconfiguration
2. **Scalability**: Add new VNets without physical network changes
3. **Isolation**: L2 isolation between VNets
4. **Flexibility**: Easy to add/remove VNets, change addressing
5. **Distributed Gateways**: Local routing on each PVE host (no hairpinning)
6. **Redundancy**: All PVE hosts are exit nodes (no SPOF)

## Limitations

1. **MTU Reduction**: 1450 instead of 1500 (VXLAN overhead)
2. **VM Recreation**: Switching to/from SDN requires VM recreation
3. **FRR Dependency**: Requires FRR properly configured before SDN
4. **IPv6 Only**: Current implementation uses IPv6 subnets only
5. **No Live Migration**: Cannot migrate running VMs when changing network type

## References

- [Proxmox SDN Documentation](https://pve.proxmox.com/wiki/Software-Defined_Network)
- [FRR BGP EVPN Documentation](https://docs.frrouting.org/en/stable-10.5/evpn.html)
- [RFC 7432: BGP MPLS-Based Ethernet VPN](https://datatracker.ietf.org/doc/html/rfc7432)
- [VXLAN RFC 7348](https://datatracker.ietf.org/doc/html/rfc7348)

## Related Documentation

- [Network ASN Allocation](./NETWORK_ASN_ALLOCATION.md)
- [FRR v1.0.16 Upgrade Notes](./FRR_V1.0.16_UPGRADE.md)
- [Migration from Custom FRR to Official](./MIGRATION_CUSTOM_FRR_TO_OFFICIAL.md)
