# IPv6 Internet Connectivity Implementation Plan

## Overview

Enable IPv6 internet connectivity for VMs in Proxmox SDN VNets by implementing dual-stack ULA + GUA addressing using AT&T delegated prefixes.

## Problem Statement

**Current State:**
- VMs on EVPN VNets only have ULA addresses (fd00:101::/64, etc.)
- ULA addresses are not internet-routable
- RouterOS has AT&T delegated prefixes but advertises them to old VLANs (vlan100-103), not to EVPN VNets
- VNets are isolated L2 EVPN domains that RouterOS cannot directly reach

**Required State:**
- VMs receive both ULA (stable, internal) and GUA (internet-routable) addresses
- VMs can reach IPv6 internet using GUA source addresses
- Configuration updates automatically when AT&T changes delegated prefixes

## Architecture Gap

**Before (VLANs):**
```
VM on vlan101 ← RA from RouterOS → gets both fd00:101::X (ULA) and 2600::X (GUA)
```

**Now (EVPN VNets):**
```
VM on vnet101 ← RA from ??? → only gets fd00:101::X (ULA)
                                missing: 2600::X (GUA) for internet
```

## Solution Design

### Dual-Stack Strategy

VMs will receive both address types:
1. **ULA** (fd00::/8) - Stable, for internal services and inter-cluster communication
2. **GUA** (2600::/prefix from AT&T) - Dynamic, for internet access

### Implementation Components

1. **PVE hosts add GUA addresses to VNet SVIs**
   - Example: `2600:1700:ab1a:500e::ffff/64` on vnet101
   - Matches the ::ffff gateway pattern already established

2. **radvd advertises both prefixes to VMs**
   - ULA prefix (AdvPreferredLifetime infinite - stable)
   - GUA prefix (AdvPreferredLifetime short - tracks PD changes)

3. **FRR advertises GUA subnets to RouterOS**
   - RouterOS needs routes to send return traffic to PVE hosts
   - PVE hosts forward to correct VM via EVPN

### Current AT&T Delegated Prefixes

From RouterOS (active PD for VLANs):
- vlan100 → vnet100: `2600:1700:ab1a:5009::/64`
- vlan101 → vnet101: `2600:1700:ab1a:500e::/64`
- vlan102 → vnet102: `2600:1700:ab1a:500b::/64`
- vlan103 → vnet103: `2600:1700:ab1a:5008::/64`

## Implementation Approach

### Phase 1: Manual Testing (Immediate Validation)

**Purpose:** Validate the approach works before automating

**Steps:**
1. SSH to one PVE host (pve01)
2. Add GUA address to vnet101:
   ```bash
   ip -6 addr add 2600:1700:ab1a:500e::ffff/64 dev vnet101
   ```
3. Install and configure radvd:
   ```bash
   apt install radvd
   ```
   Configure `/etc/radvd.conf` to advertise both ULA and GUA
4. Start radvd and verify VMs receive both addresses
5. Test internet connectivity from VM using GUA

**Success Criteria:**
- VM shows both fd00:101::X and 2600::X addresses
- VM can ping 2001:4860:4860::8888 (Google DNS)
- `curl -6 https://ifconfig.co` returns GUA address

### Phase 2: Ansible Deployment (Production Rollout)

**Purpose:** Deploy configuration to all PVE hosts

**New Ansible Role:** `ansible/lae.proxmox/roles/ipv6_gua_config/`

**Tasks:**
1. Create script template to add GUA addresses to VNets
2. Deploy radvd configuration with both ULA and GUA prefixes
3. Update FRR configuration to advertise GUA prefixes
4. Deploy to all PVE hosts via playbook

**Files to Create:**
- `roles/ipv6_gua_config/tasks/main.yaml`
- `roles/ipv6_gua_config/templates/radvd.conf.j2`
- `roles/ipv6_gua_config/templates/vnet-gua.sh.j2`
- `playbooks/configure-ipv6-gua.yml`

**Variables to Add:**
Add to `group_vars/cluster.yaml`:
```yaml
delegated_prefixes:
  vnet100: "2600:1700:ab1a:5009::/64"
  vnet101: "2600:1700:ab1a:500e::/64"
  vnet102: "2600:1700:ab1a:500b::/64"
  vnet103: "2600:1700:ab1a:5008::/64"
```

**FRR Template Updates:**
Update `roles/frr/templates/frr-pve.conf.j2` to advertise GUA prefixes:
```jinja2
{% if delegated_prefixes is defined %}
{% for vnet, prefix in delegated_prefixes.items() %}
ipv6 prefix-list PVE_CONNECTED_V6 permit {{ prefix }} le 128
{% endfor %}
{% endif %}
```

### Phase 3: Automation (Handle Prefix Changes)

**Design Decision: RouterOS as Source of Truth**

Since RouterOS is the DHCPv6-PD client that receives prefix updates from AT&T, it's the authoritative source. The most reliable approach is to have RouterOS push updates to PVE when prefixes change.

#### Option A: RouterOS Script with PVE API (Recommended)

**Architecture:**
```
AT&T DHCPv6-PD → RouterOS receives new prefix
                      ↓
                 RouterOS script triggered
                      ↓
                 Calls PVE API to update VNet config
                      ↓
                 Triggers Ansible deployment
```

**Implementation:**

**RouterOS Script:** `/system/script/pve-prefix-update`
```routeros
# RouterOS script triggered on DHCPv6-PD prefix change
:local vnetMap {
  "vlan100"="vnet100";
  "vlan101"="vnet101";
  "vlan102"="vnet102";
  "vlan103"="vnet103"
}

# Get the VLAN that received new prefix
:local vlanIf $interface
:local vnetName ($vnetMap->$vlanIf)

# Get the new prefix
:local newPrefix [/ipv6/dhcp-client/get [find interface=$vlanIf] prefix]

:log info "DHCPv6-PD prefix changed for $vlanIf -> $vnetName: $newPrefix"

# Trigger update on PVE management host (could use webhook or SSH)
# Option 1: Webhook to automation service
/tool fetch mode=https url="https://automation.sulibot.com/update-vnet-prefix?vnet=$vnetName&prefix=$newPrefix"

# Option 2: SSH to trigger Ansible
/system ssh user=automation address=10.0.10.1 command="ansible-playbook /path/to/update-ipv6-gua.yml -e vnet=$vnetName -e prefix=$newPrefix"

# Option 3: Update git repo and trigger CI/CD
# (Most robust - ensures version control)
```

**Attach to DHCPv6 Clients:**
```routeros
/ipv6/dhcp-client
set [find interface=vlan100] script=pve-prefix-update
set [find interface=vlan101] script=pve-prefix-update
set [find interface=vlan102] script=pve-prefix-update
set [find interface=vlan103] script=pve-prefix-update
```

**Benefits:**
- RouterOS is source of truth (no polling needed)
- Immediate updates when AT&T changes prefixes
- Can trigger existing Ansible automation
- Reliable (DHCPv6-PD client script is well-tested RouterOS feature)

#### Option B: Terraform External Data Source (Polling)

**Architecture:**
```
Terraform (periodic) → Query RouterOS API
                            ↓
                       Parse current PD prefixes
                            ↓
                       Update variables file
                            ↓
                       Trigger Ansible deployment
```

**Files to Create:**
- `terraform/infra/modules/ipv6_prefix_sync/main.tf`
- `terraform/infra/modules/ipv6_prefix_sync/query_routeros.py`
- `terraform/infra/live/common/1-ipv6-prefix-sync/terragrunt.hcl`

**GitHub Actions Workflow:**
```yaml
# .github/workflows/sync-ipv6-prefixes.yml
name: Sync IPv6 Prefixes
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  sync:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Query RouterOS and update prefixes
        run: |
          cd terraform/infra/live/common/1-ipv6-prefix-sync
          terragrunt apply -auto-approve
      - name: Deploy via Ansible
        run: |
          cd ansible/lae.proxmox
          ansible-playbook -i inventory/hosts.ini playbooks/configure-ipv6-gua.yml
      - name: Commit changes
        run: |
          git add ansible/lae.proxmox/group_vars/cluster.yaml
          git commit -m "chore: update IPv6 delegated prefixes" || true
          git push
```

**Drawbacks:**
- Polling introduces delay (prefixes could change between checks)
- More complex (Terraform + Python script + GitHub Actions)
- Requires RouterOS API credentials management

#### Option C: Manual Variable File (Simplest)

**File:** `terraform/infra/live/common/ipv6-prefixes.hcl`
```hcl
locals {
  # Update manually when AT&T changes PD
  delegated_prefixes = {
    vnet100 = "2600:1700:ab1a:5009::/64"
    vnet101 = "2600:1700:ab1a:500e::/64"
    vnet102 = "2600:1700:ab1a:500b::/64"
    vnet103 = "2600:1700:ab1a:5008::/64"
  }
}
```

**Include in Ansible:**
```hcl
# ansible/lae.proxmox/group_vars/cluster.yaml
delegated_prefixes: "{{ lookup('file', '../../terraform/infra/live/common/ipv6-prefixes.hcl') | from_hcl }}"
```

**Benefits:**
- Simple, no automation complexity
- Easy to update manually when needed
- Version controlled

**Drawbacks:**
- Requires manual intervention when AT&T changes prefixes
- Could have downtime if prefix change not noticed immediately

### Recommended Automation Approach: Hybrid

**Phase 3a: Start with Manual Variables (Week 1)**
- Deploy using Option C (manual variable file)
- Validate everything works in production
- Monitor for prefix changes from AT&T

**Phase 3b: Add RouterOS Script Push (Week 2-3)**
- Implement Option A (RouterOS script)
- Script updates git repo and triggers CI/CD
- Maintains version control while automating updates

**Workflow:**
```
AT&T changes prefix → RouterOS DHCPv6-PD receives update
                           ↓
                      RouterOS script runs
                           ↓
                      Updates git repo via SSH/API
                           ↓
                      GitHub Actions triggered
                           ↓
                      Ansible deploys new configuration
                           ↓
                      VMs receive new GUA via radvd RA
```

## Critical Files

### Files to Create

**Ansible:**
- `ansible/lae.proxmox/roles/ipv6_gua_config/tasks/main.yaml`
- `ansible/lae.proxmox/roles/ipv6_gua_config/templates/radvd.conf.j2`
- `ansible/lae.proxmox/roles/ipv6_gua_config/templates/vnet-gua.sh.j2`
- `ansible/lae.proxmox/roles/ipv6_gua_config/handlers/main.yaml`
- `ansible/lae.proxmox/playbooks/configure-ipv6-gua.yml`

**Terraform:**
- `terraform/infra/live/common/ipv6-prefixes.hcl` (manual variables)

**RouterOS:**
- Script: `/system/script/pve-prefix-update` (DHCPv6-PD hook)

**GitHub Actions:**
- `.github/workflows/ipv6-prefix-update.yml` (triggered by RouterOS)

### Files to Modify

**Ansible:**
- `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2` - Add GUA prefix-lists
- `ansible/lae.proxmox/group_vars/cluster.yaml` - Add delegated_prefixes variable

**Documentation:**
- `docs/PROXMOX_SDN_EVPN_SETUP.md` - Document IPv6 GUA configuration
- `docs/NETWORK_ASN_ALLOCATION.md` - Add IPv6 prefix allocation table

## Implementation Order

**APPROVED BY USER - READY FOR EXECUTION**

User directive: "execute this plan - use the PD prefixes you already have from AT&T, and if they're not available for some reason, fall back to NAT66. also add the default route for talos VMs and comment out the fc00::/7 route"

### Phase 1: Create Terraform Variables and Ansible Role
1. ✅ Create `terraform/infra/live/common/ipv6-prefixes.hcl` with AT&T PD prefixes
2. Create `ansible/lae.proxmox/roles/ipv6_gua_config/` role structure
3. Create script template to add GUA addresses to VNets (`vnet-gua.sh.j2`)
4. Create radvd configuration template (`radvd.conf.j2`)
5. Add delegated_prefixes to `group_vars/cluster.yaml`

### Phase 2: Update FRR Templates
1. Update PVE FRR template to advertise GUA prefixes to RouterOS
2. Update Talos FRR template:
   - Add default route origination from PVE gateway
   - Comment out fc00::/7 route

### Phase 3: Deploy Configuration
1. Create `playbooks/configure-ipv6-gua.yml` playbook
2. Deploy to all PVE hosts via Ansible
3. Verify VNets have both ULA and GUA addresses
4. Verify radvd is advertising both prefixes

### Phase 4: Verification
1. Check VMs receive both ULA and GUA addresses
2. Test IPv6 internet connectivity from VMs
3. Verify BGP advertises GUA subnets to RouterOS
4. Test VM can reach internet using GUA source address

## Success Criteria

- [ ] VMs receive both ULA and GUA addresses via SLAAC
- [ ] VMs can ping 2001:4860:4860::8888 (Google DNS)
- [ ] `curl -6 https://ifconfig.co` from VM returns GUA address
- [ ] BGP advertises GUA subnets to RouterOS
- [ ] RouterOS has routes for GUA subnets pointing to PVE hosts
- [ ] Configuration survives PVE host reboot
- [ ] When AT&T changes prefix, update completes within 5 minutes
- [ ] All changes are version controlled in git

## Fallback: NAT66

If delegated prefixes become unavailable (AT&T outage, RouterOS down), configure NAT66 on RouterOS:

```routeros
/ipv6 firewall nat
add chain=srcnat src-address=fd00:100::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::1 comment="NAT66 vnet100"
add chain=srcnat src-address=fd00:101::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::2 comment="NAT66 vnet101"
add chain=srcnat src-address=fd00:102::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::3 comment="NAT66 vnet102"
add chain=srcnat src-address=fd00:103::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::4 comment="NAT66 vnet103"
```

**Note:** NAT66 is not needed immediately since PD is working. This is documented for future reference only.

## Risk Mitigation

1. **Prefix Changes**: RouterOS script ensures automatic updates
2. **VM Connectivity Loss**: Graceful fallback - ULA still works for internal traffic
3. **radvd Failure**: VMs retain existing GUA addresses (valid for lease time)
4. **PVE Host Failure**: Anycast gateway on remaining hosts continues to work
5. **AT&T PD Loss**: Document NAT66 fallback procedure (not implementing initially)

## Rollback Plan

If GUA implementation causes issues:
1. Stop radvd on all PVE hosts
2. Remove GUA addresses from VNet SVIs
3. VMs continue working with ULA (internal traffic only)
4. Remove GUA prefix-lists from FRR configuration

No VM recreation needed - address removal is graceful.
# IPv6 Internet Connectivity Implementation Plan

## Overview

Enable IPv6 internet connectivity for VMs in Proxmox SDN VNets by implementing dual-stack ULA + GUA addressing using AT&T delegated prefixes.

## Problem Statement

**Current State:**
- VMs on EVPN VNets only have ULA addresses (fd00:101::/64, etc.)
- ULA addresses are not internet-routable
- RouterOS has AT&T delegated prefixes but advertises them to old VLANs (vlan100-103), not to EVPN VNets
- VNets are isolated L2 EVPN domains that RouterOS cannot directly reach

**Required State:**
- VMs receive both ULA (stable, internal) and GUA (internet-routable) addresses
- VMs can reach IPv6 internet using GUA source addresses
- Configuration updates automatically when AT&T changes delegated prefixes

## Architecture Gap

**Before (VLANs):**
```
VM on vlan101 ← RA from RouterOS → gets both fd00:101::X (ULA) and 2600::X (GUA)
```

**Now (EVPN VNets):**
```
VM on vnet101 ← RA from ??? → only gets fd00:101::X (ULA)
                                missing: 2600::X (GUA) for internet
```

## Solution Design

### Dual-Stack Strategy

VMs will receive both address types:
1. **ULA** (fd00::/8) - Stable, for internal services and inter-cluster communication
2. **GUA** (2600::/prefix from AT&T) - Dynamic, for internet access

### Implementation Components

1. **PVE hosts add GUA addresses to VNet SVIs**
   - Example: `2600:1700:ab1a:500e::ffff/64` on vnet101
   - Matches the ::ffff gateway pattern already established

2. **radvd advertises both prefixes to VMs**
   - ULA prefix (AdvPreferredLifetime infinite - stable)
   - GUA prefix (AdvPreferredLifetime short - tracks PD changes)

3. **FRR advertises GUA subnets to RouterOS**
   - RouterOS needs routes to send return traffic to PVE hosts
   - PVE hosts forward to correct VM via EVPN

### Current AT&T Delegated Prefixes

From RouterOS (active PD for VLANs):
- vlan100 → vnet100: `2600:1700:ab1a:5009::/64`
- vlan101 → vnet101: `2600:1700:ab1a:500e::/64`
- vlan102 → vnet102: `2600:1700:ab1a:500b::/64`
- vlan103 → vnet103: `2600:1700:ab1a:5008::/64`

## Implementation Approach

### Phase 1: Manual Testing (Immediate Validation)

**Purpose:** Validate the approach works before automating

**Steps:**
1. SSH to one PVE host (pve01)
2. Add GUA address to vnet101:
   ```bash
   ip -6 addr add 2600:1700:ab1a:500e::ffff/64 dev vnet101
   ```
3. Install and configure radvd:
   ```bash
   apt install radvd
   ```
   Configure `/etc/radvd.conf` to advertise both ULA and GUA
4. Start radvd and verify VMs receive both addresses
5. Test internet connectivity from VM using GUA

**Success Criteria:**
- VM shows both fd00:101::X and 2600::X addresses
- VM can ping 2001:4860:4860::8888 (Google DNS)
- `curl -6 https://ifconfig.co` returns GUA address

### Phase 2: Ansible Deployment (Production Rollout)

**Purpose:** Deploy configuration to all PVE hosts

**New Ansible Role:** `ansible/lae.proxmox/roles/ipv6_gua_config/`

**Tasks:**
1. Create script template to add GUA addresses to VNets
2. Deploy radvd configuration with both ULA and GUA prefixes
3. Update FRR configuration to advertise GUA prefixes
4. Deploy to all PVE hosts via playbook

**Files to Create:**
- `roles/ipv6_gua_config/tasks/main.yaml`
- `roles/ipv6_gua_config/templates/radvd.conf.j2`
- `roles/ipv6_gua_config/templates/vnet-gua.sh.j2`
- `playbooks/configure-ipv6-gua.yml`

**Variables to Add:**
Add to `group_vars/cluster.yaml`:
```yaml
delegated_prefixes:
  vnet100: "2600:1700:ab1a:5009::/64"
  vnet101: "2600:1700:ab1a:500e::/64"
  vnet102: "2600:1700:ab1a:500b::/64"
  vnet103: "2600:1700:ab1a:5008::/64"
```

**FRR Template Updates:**
Update `roles/frr/templates/frr-pve.conf.j2` to advertise GUA prefixes:
```jinja2
{% if delegated_prefixes is defined %}
{% for vnet, prefix in delegated_prefixes.items() %}
ipv6 prefix-list PVE_CONNECTED_V6 permit {{ prefix }} le 128
{% endfor %}
{% endif %}
```

### Phase 3: Automation (Handle Prefix Changes)

**Design Decision: RouterOS as Source of Truth**

Since RouterOS is the DHCPv6-PD client that receives prefix updates from AT&T, it's the authoritative source. The most reliable approach is to have RouterOS push updates to PVE when prefixes change.

#### Option A: RouterOS Script with PVE API (Recommended)

**Architecture:**
```
AT&T DHCPv6-PD → RouterOS receives new prefix
                      ↓
                 RouterOS script triggered
                      ↓
                 Calls PVE API to update VNet config
                      ↓
                 Triggers Ansible deployment
```

**Implementation:**

**RouterOS Script:** `/system/script/pve-prefix-update`
```routeros
# RouterOS script triggered on DHCPv6-PD prefix change
:local vnetMap {
  "vlan100"="vnet100";
  "vlan101"="vnet101";
  "vlan102"="vnet102";
  "vlan103"="vnet103"
}

# Get the VLAN that received new prefix
:local vlanIf $interface
:local vnetName ($vnetMap->$vlanIf)

# Get the new prefix
:local newPrefix [/ipv6/dhcp-client/get [find interface=$vlanIf] prefix]

:log info "DHCPv6-PD prefix changed for $vlanIf -> $vnetName: $newPrefix"

# Trigger update on PVE management host (could use webhook or SSH)
# Option 1: Webhook to automation service
/tool fetch mode=https url="https://automation.sulibot.com/update-vnet-prefix?vnet=$vnetName&prefix=$newPrefix"

# Option 2: SSH to trigger Ansible
/system ssh user=automation address=10.0.10.1 command="ansible-playbook /path/to/update-ipv6-gua.yml -e vnet=$vnetName -e prefix=$newPrefix"

# Option 3: Update git repo and trigger CI/CD
# (Most robust - ensures version control)
```

**Attach to DHCPv6 Clients:**
```routeros
/ipv6/dhcp-client
set [find interface=vlan100] script=pve-prefix-update
set [find interface=vlan101] script=pve-prefix-update
set [find interface=vlan102] script=pve-prefix-update
set [find interface=vlan103] script=pve-prefix-update
```

**Benefits:**
- RouterOS is source of truth (no polling needed)
- Immediate updates when AT&T changes prefixes
- Can trigger existing Ansible automation
- Reliable (DHCPv6-PD client script is well-tested RouterOS feature)

#### Option B: Terraform External Data Source (Polling)

**Architecture:**
```
Terraform (periodic) → Query RouterOS API
                            ↓
                       Parse current PD prefixes
                            ↓
                       Update variables file
                            ↓
                       Trigger Ansible deployment
```

**Files to Create:**
- `terraform/infra/modules/ipv6_prefix_sync/main.tf`
- `terraform/infra/modules/ipv6_prefix_sync/query_routeros.py`
- `terraform/infra/live/common/1-ipv6-prefix-sync/terragrunt.hcl`

**GitHub Actions Workflow:**
```yaml
# .github/workflows/sync-ipv6-prefixes.yml
name: Sync IPv6 Prefixes
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  sync:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Query RouterOS and update prefixes
        run: |
          cd terraform/infra/live/common/1-ipv6-prefix-sync
          terragrunt apply -auto-approve
      - name: Deploy via Ansible
        run: |
          cd ansible/lae.proxmox
          ansible-playbook -i inventory/hosts.ini playbooks/configure-ipv6-gua.yml
      - name: Commit changes
        run: |
          git add ansible/lae.proxmox/group_vars/cluster.yaml
          git commit -m "chore: update IPv6 delegated prefixes" || true
          git push
```

**Drawbacks:**
- Polling introduces delay (prefixes could change between checks)
- More complex (Terraform + Python script + GitHub Actions)
- Requires RouterOS API credentials management

#### Option C: Manual Variable File (Simplest)

**File:** `terraform/infra/live/common/ipv6-prefixes.hcl`
```hcl
locals {
  # Update manually when AT&T changes PD
  delegated_prefixes = {
    vnet100 = "2600:1700:ab1a:5009::/64"
    vnet101 = "2600:1700:ab1a:500e::/64"
    vnet102 = "2600:1700:ab1a:500b::/64"
    vnet103 = "2600:1700:ab1a:5008::/64"
  }
}
```

**Include in Ansible:**
```hcl
# ansible/lae.proxmox/group_vars/cluster.yaml
delegated_prefixes: "{{ lookup('file', '../../terraform/infra/live/common/ipv6-prefixes.hcl') | from_hcl }}"
```

**Benefits:**
- Simple, no automation complexity
- Easy to update manually when needed
- Version controlled

**Drawbacks:**
- Requires manual intervention when AT&T changes prefixes
- Could have downtime if prefix change not noticed immediately

### Recommended Automation Approach: Hybrid

**Phase 3a: Start with Manual Variables (Week 1)**
- Deploy using Option C (manual variable file)
- Validate everything works in production
- Monitor for prefix changes from AT&T

**Phase 3b: Add RouterOS Script Push (Week 2-3)**
- Implement Option A (RouterOS script)
- Script updates git repo and triggers CI/CD
- Maintains version control while automating updates

**Workflow:**
```
AT&T changes prefix → RouterOS DHCPv6-PD receives update
                           ↓
                      RouterOS script runs
                           ↓
                      Updates git repo via SSH/API
                           ↓
                      GitHub Actions triggered
                           ↓
                      Ansible deploys new configuration
                           ↓
                      VMs receive new GUA via radvd RA
```

## Critical Files

### Files to Create

**Ansible:**
- `ansible/lae.proxmox/roles/ipv6_gua_config/tasks/main.yaml`
- `ansible/lae.proxmox/roles/ipv6_gua_config/templates/radvd.conf.j2`
- `ansible/lae.proxmox/roles/ipv6_gua_config/templates/vnet-gua.sh.j2`
- `ansible/lae.proxmox/roles/ipv6_gua_config/handlers/main.yaml`
- `ansible/lae.proxmox/playbooks/configure-ipv6-gua.yml`

**Terraform:**
- `terraform/infra/live/common/ipv6-prefixes.hcl` (manual variables)

**RouterOS:**
- Script: `/system/script/pve-prefix-update` (DHCPv6-PD hook)

**GitHub Actions:**
- `.github/workflows/ipv6-prefix-update.yml` (triggered by RouterOS)

### Files to Modify

**Ansible:**
- `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2` - Add GUA prefix-lists
- `ansible/lae.proxmox/group_vars/cluster.yaml` - Add delegated_prefixes variable

**Documentation:**
- `docs/PROXMOX_SDN_EVPN_SETUP.md` - Document IPv6 GUA configuration
- `docs/NETWORK_ASN_ALLOCATION.md` - Add IPv6 prefix allocation table

## Implementation Order

**APPROVED BY USER - READY FOR EXECUTION**

User directive: "execute this plan - use the PD prefixes you already have from AT&T, and if they're not available for some reason, fall back to NAT66. also add the default route for talos VMs and comment out the fc00::/7 route"

### Phase 1: Create Terraform Variables and Ansible Role
1. ✅ Create `terraform/infra/live/common/ipv6-prefixes.hcl` with AT&T PD prefixes
2. Create `ansible/lae.proxmox/roles/ipv6_gua_config/` role structure
3. Create script template to add GUA addresses to VNets (`vnet-gua.sh.j2`)
4. Create radvd configuration template (`radvd.conf.j2`)
5. Add delegated_prefixes to `group_vars/cluster.yaml`

### Phase 2: Update FRR Templates
1. Update PVE FRR template to advertise GUA prefixes to RouterOS
2. Update Talos FRR template:
   - Add default route origination from PVE gateway
   - Comment out fc00::/7 route

### Phase 3: Deploy Configuration
1. Create `playbooks/configure-ipv6-gua.yml` playbook
2. Deploy to all PVE hosts via Ansible
3. Verify VNets have both ULA and GUA addresses
4. Verify radvd is advertising both prefixes

### Phase 4: Verification
1. Check VMs receive both ULA and GUA addresses
2. Test IPv6 internet connectivity from VMs
3. Verify BGP advertises GUA subnets to RouterOS
4. Test VM can reach internet using GUA source address

## Success Criteria

- [ ] VMs receive both ULA and GUA addresses via SLAAC
- [ ] VMs can ping 2001:4860:4860::8888 (Google DNS)
- [ ] `curl -6 https://ifconfig.co` from VM returns GUA address
- [ ] BGP advertises GUA subnets to RouterOS
- [ ] RouterOS has routes for GUA subnets pointing to PVE hosts
- [ ] Configuration survives PVE host reboot
- [ ] When AT&T changes prefix, update completes within 5 minutes
- [ ] All changes are version controlled in git

## Fallback: NAT66

If delegated prefixes become unavailable (AT&T outage, RouterOS down), configure NAT66 on RouterOS:

```routeros
/ipv6 firewall nat
add chain=srcnat src-address=fd00:100::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::1 comment="NAT66 vnet100"
add chain=srcnat src-address=fd00:101::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::2 comment="NAT66 vnet101"
add chain=srcnat src-address=fd00:102::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::3 comment="NAT66 vnet102"
add chain=srcnat src-address=fd00:103::/64 action=src-nat to-addresses=2600:1700:ab1a:500c::4 comment="NAT66 vnet103"
```

**Note:** NAT66 is not needed immediately since PD is working. This is documented for future reference only.

## Risk Mitigation

1. **Prefix Changes**: RouterOS script ensures automatic updates
2. **VM Connectivity Loss**: Graceful fallback - ULA still works for internal traffic
3. **radvd Failure**: VMs retain existing GUA addresses (valid for lease time)
4. **PVE Host Failure**: Anycast gateway on remaining hosts continues to work
5. **AT&T PD Loss**: Document NAT66 fallback procedure (not implementing initially)

## Rollback Plan

If GUA implementation causes issues:
1. Stop radvd on all PVE hosts
2. Remove GUA addresses from VNet SVIs
3. VMs continue working with ULA (internal traffic only)
4. Remove GUA prefix-lists from FRR configuration

No VM recreation needed - address removal is graceful.
