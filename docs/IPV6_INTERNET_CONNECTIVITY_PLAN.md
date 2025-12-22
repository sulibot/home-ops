# IPv6 Internet Connectivity for Proxmox SDN VNets

## Current Status

### What's Working
- ✅ Proxmox SDN EVPN configured with 4 VNets (vnet100-103)
- ✅ VMs have ULA addresses (fd00:100::/64, fd00:101::/64, etc.)
- ✅ L2 connectivity within VNets via EVPN/VXLAN
- ✅ BGP route leaking from VRF to main table (fd00:X::/64 subnets advertised to RouterOS)
- ✅ IPv6 BGP sessions established to RouterOS (fd00:10::ffff)
- ✅ RouterOS has delegated prefixes from AT&T for each VLAN:
  - vnet100: `2600:1700:ab1a:5009::/64` (pool: pd-v100)
  - vnet101: `2600:1700:ab1a:500e::/64` (pool: pd-v101)
  - vnet102: `2600:1700:ab1a:500b::/64` (pool: pd-v102)
  - vnet103: `2600:1700:ab1a:5008::/64` (pool: pd-v103)

### What's Not Working
- ❌ VMs cannot reach the internet (ULA addresses are not routable)
- ❌ RouterOS advertises GUA via RA to old VLANs (vlan100-103), not to EVPN VNets
- ❌ VNets don't have GUA addresses configured
- ❌ No radvd on PVE to advertise GUA to VMs

### Architecture Gap

```
Before (VLANs):
VM ← RA from RouterOS → gets both fd00:101::X (ULA) and 2600::X (GUA)

Now (EVPN):
VM ← RA from ??? → only gets fd00:101::X (ULA)
                    missing: 2600::X (GUA) for internet access
```

## Solution: Dual-Stack ULA + GUA with Dynamic PD

### Strategy
1. **Primary**: Use AT&T delegated prefixes (PD) when available
2. **Fallback**: Use NAT66 if PD unavailable (automatic failover)
3. **VMs get both**:
   - ULA (fd00:101::X) - stable, for internal services
   - GUA (2600::X) - dynamic, for internet access

### Implementation Approach

#### Phase 1: Manual GUA Configuration (Quick Fix)
Add GUA addresses to VNets manually, verify connectivity works.

**On each PVE host**, run script to:
1. Add GUA address to VNet SVI: `ip -6 addr add 2600:1700:ab1a:500e::ffff/64 dev vnet101`
2. Enable IPv6 forwarding: `sysctl -w net.ipv6.conf.vnet101.forwarding=1`
3. Configure kernel RA (temporary): Enable accept_ra and send RA packets

**Verification**:
- VMs should receive RA with both ULA and GUA prefixes
- VMs should be able to ping internet via GUA address
- Confirm routes are advertised to RouterOS via BGP

#### Phase 2: Terraform-Managed Configuration (Permanent Solution)

**Option A: Terraform External Data Source + Ansible Deployment**

Create automated system to:
1. Query RouterOS API for current PD prefixes
2. Update Terraform variables with current prefixes
3. Deploy configuration changes via Ansible

**File Structure**:
```
terraform/infra/modules/ipv6_prefix_sync/
├── main.tf              # External data source from RouterOS
├── outputs.tf           # Export prefix mappings
└── variables.tf         # VNet list, RouterOS endpoint

terraform/infra/live/common/1-ipv6-prefix-sync/
└── terragrunt.hcl       # Call prefix_sync module

ansible/lae.proxmox/roles/ipv6_gua_config/
├── tasks/main.yaml      # Deploy GUA to VNets
├── templates/
│   ├── vnet-gua.sh.j2   # Script to add GUA addresses
│   └── radvd.conf.j2    # RA daemon config
└── handlers/main.yaml   # Restart radvd, reload network
```

**Workflow**:
```bash
# Step 1: Terraform fetches current PD from RouterOS
cd terraform/infra/live/common/1-ipv6-prefix-sync
terragrunt apply
# Outputs: prefix_map = { vnet100 = "2600:...", vnet101 = "2600:..." }

# Step 2: Ansible deploys GUA configuration
cd ansible/lae.proxmox
ansible-playbook -i inventory/hosts.ini playbooks/configure-ipv6-gua.yml
# Reads Terraform outputs, configures VNets + radvd
```

**Option B: Terraform Variables File + Manual Updates**

Simpler approach for initial implementation:

**File**: `terraform/infra/live/common/ipv6-prefixes.hcl`
```hcl
locals {
  # Updated manually when AT&T changes PD
  # Or via script that queries RouterOS
  delegated_prefixes = {
    vnet100 = "2600:1700:ab1a:5009::/64"
    vnet101 = "2600:1700:ab1a:500e::/64"
    vnet102 = "2600:1700:ab1a:500b::/64"
    vnet103 = "2600:1700:ab1a:5008::/64"
  }
}
```

**Include in SDN setup**:
```hcl
# terraform/infra/live/common/0-sdn-setup/terragrunt.hcl
include "ipv6_prefixes" {
  path = find_in_parent_folders("common/ipv6-prefixes.hcl")
}

inputs = {
  vnets = {
    vnet101 = {
      alias       = "Talos Cluster 101"
      vxlan_id    = 10101
      subnet_ula  = "fd00:101::/64"
      gateway_ula = "fd00:101::ffff"
      subnet_gua  = local.delegated_prefixes.vnet101  # Dynamic!
      gateway_gua = "${trimsuffix(local.delegated_prefixes.vnet101, "::/64")}::ffff"
    }
    # ... other vnets
  }
}
```

### NAT66 Fallback Configuration

If PD unavailable (AT&T outage, RouterOS down), configure NAT66 on RouterOS as backup.

**RouterOS NAT66 Configuration**:
```routeros
# Translate ULA to single GUA address for outbound traffic
/ipv6 firewall nat
add chain=srcnat src-address=fd00:100::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::1 comment="NAT66 vnet100"
add chain=srcnat src-address=fd00:101::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::2 comment="NAT66 vnet101"
add chain=srcnat src-address=fd00:102::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::3 comment="NAT66 vnet102"
add chain=srcnat src-address=fd00:103::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::4 comment="NAT66 vnet103"
```

**Detection Logic** (on PVE or RouterOS):
```bash
# Check if PD is active
if [[ -n "$(ip -6 addr show dev vnet101 | grep '2600:')" ]]; then
  echo "Using PD - Native IPv6"
else
  echo "PD unavailable - NAT66 active"
fi
```

## Detailed Implementation Steps

### Step 1: Add GUA to VNets (Manual - Immediate)

Run on each PVE host:

```bash
#!/bin/bash
# /usr/local/bin/add-vnet-gua.sh

# VNet 100
ip -6 addr add 2600:1700:ab1a:5009::ffff/64 dev vnet100 2>/dev/null || true
# VNet 101
ip -6 addr add 2600:1700:ab1a:500e::ffff/64 dev vnet101 2>/dev/null || true
# VNet 102
ip -6 addr add 2600:1700:ab1a:500b::ffff/64 dev vnet102 2>/dev/null || true
# VNet 103
ip -6 addr add 2600:1700:ab1a:5008::ffff/64 dev vnet103 2>/dev/null || true

# Enable forwarding on all VNets
for vnet in vnet100 vnet101 vnet102 vnet103; do
  sysctl -w net.ipv6.conf.$vnet.forwarding=1
done

echo "GUA addresses added to VNets"
```

### Step 2: Configure radvd for GUA Advertisement

Install and configure radvd:

```bash
apt install radvd
```

**File**: `/etc/radvd.conf`
```conf
# VNet 101 - Talos Cluster 101
interface vnet101 {
    AdvSendAdvert on;
    AdvManagedFlag off;
    AdvOtherConfigFlag off;
    MinRtrAdvInterval 30;
    MaxRtrAdvInterval 60;

    # ULA - stable for internal services
    prefix fd00:101::/64 {
        AdvOnLink on;
        AdvAutonomous on;
        AdvRouterAddr off;
    };

    # GUA - for internet access (from AT&T PD)
    prefix 2600:1700:ab1a:500e::/64 {
        AdvOnLink on;
        AdvAutonomous on;
        AdvRouterAddr off;
        AdvValidLifetime 300;
        AdvPreferredLifetime 120;
    };

    RDNSS fd00:101::ffff {
        AdvRDNSSLifetime 60;
    };
};

# Repeat for vnet100, vnet102, vnet103...
```

Enable and start:
```bash
systemctl enable radvd
systemctl start radvd
```

### Step 3: Update FRR to Advertise GUA Subnets

**File**: `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

Add GUA prefixes to export list:

```jinja2
! Export both ULA and GUA prefixes
ipv6 prefix-list PVE_CONNECTED_V6 permit fd00:10::/64  le 128
ipv6 prefix-list PVE_CONNECTED_V6 permit fd00:255::/48 le 128
ipv6 prefix-list PVE_CONNECTED_V6 permit fc00:20::/64  le 128
ipv6 prefix-list PVE_CONNECTED_V6 permit fc00:21::/64  le 128

{# Add GUA prefixes from delegated ranges #}
{% if delegated_prefixes is defined %}
{% for vnet, prefix in delegated_prefixes.items() %}
ipv6 prefix-list PVE_CONNECTED_V6 permit {{ prefix }} le 128
{% endfor %}
{% endif %}

{% for vlan_id in TENANT_VLANS | sort %}
ipv6 prefix-list PVE_CONNECTED_V6 permit fd00:{{ vlan_id }}::/64 le 128
{% endfor %}
ipv6 prefix-list PVE_CONNECTED_V6 deny   ::/0 le 128
```

### Step 4: Verify End-to-End Connectivity

From a VM:

```bash
# Check addresses
ip -6 addr show
# Should see both:
# - inet6 fd00:101::xxxx/64 scope global (ULA)
# - inet6 2600:1700:ab1a:500e::xxxx/64 scope global (GUA)

# Check default route
ip -6 route show default
# Should show: default via fe80::... dev ens18 metric 1024

# Test internet connectivity
ping6 -c 3 2001:4860:4860::8888  # Google DNS
curl -6 https://ipv6.google.com

# Verify which address is used for outbound
curl -6 https://ifconfig.co
# Should return: 2600:1700:ab1a:500e::xxxx
```

From PVE:

```bash
# Verify VNet has both addresses
ip -6 addr show dev vnet101

# Check BGP routes advertised to RouterOS
vtysh -c "show bgp ipv6 unicast neighbors fd00:10::ffff advertised-routes" | grep 2600

# Verify radvd is sending RAs
tcpdump -i vnet101 -n icmp6 and 'icmp6[0] == 134'
```

## Automation: Handling AT&T Prefix Changes

### Option 1: Periodic Terraform + Ansible Run

GitHub Actions workflow runs daily:

```yaml
# .github/workflows/sync-ipv6-prefixes.yml
name: Sync IPv6 Prefixes
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  workflow_dispatch:      # Manual trigger

jobs:
  sync-prefixes:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - name: Query RouterOS for current PD
        run: |
          ssh admin@fd00:10::ffff "/ipv6/pool/print detail" > /tmp/ros-pools.txt

      - name: Update Terraform variables
        run: |
          # Parse RouterOS output, update ipv6-prefixes.hcl
          ./scripts/update-ipv6-prefixes.sh

      - name: Apply Terraform
        run: |
          cd terraform/infra/live/common/0-sdn-setup
          terragrunt apply -auto-approve

      - name: Deploy via Ansible
        run: |
          cd ansible/lae.proxmox
          ansible-playbook -i inventory/hosts.ini playbooks/configure-ipv6-gua.yml

      - name: Commit changes if any
        run: |
          git add terraform/infra/live/common/ipv6-prefixes.hcl
          git commit -m "chore: update IPv6 delegated prefixes" || true
          git push
```

### Option 2: RouterOS Script Hook

RouterOS runs script when DHCP-PD prefix changes:

```routeros
# /system/script
add name=update-pve-prefixes source={
  :local newPrefix [/ipv6/dhcp-client/get [find interface=wan6-v101] prefix]
  :log info "IPv6 PD changed for vlan101: $newPrefix"

  # Trigger update on PVE via webhook or SSH
  /tool fetch url="https://homeops-webhook.example.com/update-prefix?vnet=101&prefix=$newPrefix" mode=https
}

# Attach to DHCP client
/ipv6/dhcp-client
set [find interface=wan6-v101] script=update-pve-prefixes
```

## Files to Create/Modify

### Terraform
- [ ] `terraform/infra/live/common/ipv6-prefixes.hcl` - Delegated prefix variables
- [ ] `terraform/infra/modules/ipv6_prefix_sync/main.tf` - (Optional) External data source
- [ ] `terraform/infra/live/common/0-sdn-setup/terragrunt.hcl` - Include GUA config

### Ansible
- [ ] `ansible/lae.proxmox/roles/ipv6_gua_config/tasks/main.yaml` - New role
- [ ] `ansible/lae.proxmox/roles/ipv6_gua_config/templates/vnet-gua.sh.j2` - GUA setup script
- [ ] `ansible/lae.proxmox/roles/ipv6_gua_config/templates/radvd.conf.j2` - RA config
- [ ] `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2` - Update prefix-lists
- [ ] `ansible/lae.proxmox/playbooks/configure-ipv6-gua.yml` - New playbook
- [ ] `ansible/lae.proxmox/group_vars/cluster.yaml` - Add delegated_prefixes var

### Scripts
- [ ] `scripts/update-ipv6-prefixes.sh` - Parse RouterOS, update Terraform vars
- [ ] `/usr/local/bin/add-vnet-gua.sh` - Manual GUA setup (deployed via Ansible)

### Documentation
- [ ] Update `docs/PROXMOX_SDN_EVPN_SETUP.md` - Document IPv6 GUA configuration
- [ ] Update `docs/NETWORK_ASN_ALLOCATION.md` - Add IPv6 prefix allocation table

## Next Steps

1. **Immediate (Manual)**:
   - Run manual script to add GUA to VNets on all PVE hosts
   - Configure radvd on one PVE host (pve01) for testing
   - Test VM connectivity to internet via GUA

2. **Short-term (Ansible)**:
   - Create ipv6_gua_config Ansible role
   - Deploy radvd configuration to all PVE hosts
   - Update FRR templates with GUA prefix-lists
   - Test prefix changes by manually updating variables

3. **Long-term (Terraform + Automation)**:
   - Implement Terraform external data source for RouterOS API
   - Create GitHub Actions workflow for automated sync
   - Add monitoring/alerting for prefix changes
   - Document operational procedures

## Decision Points

**Question 1**: Immediate manual deployment or wait for full Terraform automation?
- **Recommend**: Manual deployment first to validate approach, then automate

**Question 2**: Use external data source or manual variable file for Terraform?
- **Recommend**: Manual variable file initially (simpler), add data source later if needed

**Question 3**: Deploy NAT66 fallback now or only when PD fails?
- **Recommend**: Document NAT66 config, but don't deploy until needed (PD is working)

**Question 4**: Configure radvd on all PVE hosts or just one?
- **Recommend**: All hosts (for redundancy when VMs migrate)

## Success Criteria

- [ ] VMs receive both ULA and GUA addresses via SLAAC
- [ ] VMs can ping internet IPv6 addresses (e.g., 2001:4860:4860::8888)
- [ ] Outbound traffic uses GUA source address (verify with curl ifconfig.co)
- [ ] BGP advertises GUA subnets to RouterOS
- [ ] RouterOS has routes for GUA subnets pointing to PVE
- [ ] Configuration survives PVE host reboot
- [ ] When AT&T changes prefix, update process takes < 5 minutes
