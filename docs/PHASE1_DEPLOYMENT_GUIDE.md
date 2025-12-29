# Phase 1 Deployment Guide - Infrastructure Loopback Renumbering

## Overview

**Branch**: `ip-renumber-phase1`
**Commit**: `e1009fba`
**Status**: Ready for deployment

This guide covers the deployment of Phase 1 infrastructure loopback renumbering as part of the IP addressing scheme v2 migration.

## What Changed

### Infrastructure Addresses
- Infrastructure loopbacks: `fd00:255::/48` → `fd00:0:0:ffff::/64`
- RouterOS IPv6: `fd00:255::fffe` → `fd00:0:0:ffff::fffe`
- RouterOS IPv4: `10.255.255.254` → `10.255.0.254`
- DNS/NTP: `fd00:255::53` → `fd00:0:0:ffff::53`

### Strategy
**Dual Addressing**: New infrastructure loopbacks are configured alongside old addresses. BGP sessions use the new addresses, but old addresses remain for safe rollback during the transition.

After verification, old addresses will be removed in a follow-up commit.

## Pre-Deployment Checklist

- [ ] All changes committed to `ip-renumber-phase1` branch
- [ ] Current BGP sessions stable and ESTABLISHED
- [ ] Backup of current PVE configurations
- [ ] RouterOS configuration access ready for manual updates
- [ ] Monitoring in place to track BGP session states

## Deployment Steps

### Step 1: Deploy to pve01 (Test Node)

```bash
cd /Users/sulibot/repos/github/home-ops

# Deploy FRR configuration to pve01
ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-frr.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini \
  --limit pve01

# Deploy network interfaces (adds new loopback)
ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-network.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini \
  --limit pve01
```

### Step 2: Verify pve01 BGP Sessions

```bash
# Check IPv4 BGP sessions
ssh root@pve01 "vtysh -c 'show bgp ipv4 summary'"

# Check IPv6 BGP sessions
ssh root@pve01 "vtysh -c 'show bgp ipv6 summary'"

# Check EVPN sessions
ssh root@pve01 "vtysh -c 'show bgp l2vpn evpn summary'"

# Verify new loopback address is configured
ssh root@pve01 "ip -6 addr show dev dummy_underlay | grep fd00:0:0:ffff"
# Should show: fd00:0:0:ffff::1/128

# Check BGP neighbor details
ssh root@pve01 "vtysh -c 'show bgp ipv6 neighbors fd00:0:0:ffff::2'"
ssh root@pve01 "vtysh -c 'show bgp ipv6 neighbors fd00:0:0:ffff::3'"
```

**Expected Results**:
- All BGP sessions ESTABLISHED
- New loopback `fd00:0:0:ffff::1/128` present
- Old loopback `fd00:255::1/128` still present
- Routes exchanged successfully

### Step 3: Deploy to pve02 and pve03

If pve01 deployment successful:

```bash
# Deploy to pve02
ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-frr.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini \
  --limit pve02

ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-network.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini \
  --limit pve02

# Verify pve02
ssh root@pve02 "vtysh -c 'show bgp summary'"

# Deploy to pve03
ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-frr.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini \
  --limit pve03

ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-network.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini \
  --limit pve03

# Verify pve03
ssh root@pve03 "vtysh -c 'show bgp summary'"
```

### Step 4: Update RouterOS

See [PHASE1_ROUTEROS_CONFIG.md](PHASE1_ROUTEROS_CONFIG.md) for detailed RouterOS configuration steps.

### Step 5: Full Verification

```bash
# Check all PVE-to-PVE BGP sessions
for host in pve01 pve02 pve03; do
  echo "=== $host ==="
  ssh root@$host "vtysh -c 'show bgp ipv6 summary' | grep fd00:0:0:ffff"
done

# Check all PVE-to-RouterOS BGP sessions
for host in pve01 pve02 pve03; do
  echo "=== $host to RouterOS ==="
  ssh root@$host "vtysh -c 'show bgp ipv6 neighbors fd00:0:0:ffff::fffe' | grep -A3 'BGP state'"
done

# Verify OSPF adjacencies
ssh root@pve01 "vtysh -c 'show ip ospf neighbor'"
ssh root@pve01 "vtysh -c 'show ipv6 ospf6 neighbor'"

# Test VM connectivity (should be unaffected)
ping -c 3 fd00:101::6  # debian-test-1
ping -c 3 fd00:101::7  # debian-test-2

# Test DNS resolution
dig @fd00:0:0:ffff::53 google.com
```

## Verification Checklist

- [ ] pve01 BGP sessions ESTABLISHED (IPv4, IPv6, EVPN)
- [ ] pve02 BGP sessions ESTABLISHED (IPv4, IPv6, EVPN)
- [ ] pve03 BGP sessions ESTABLISHED (IPv4, IPv6, EVPN)
- [ ] PVE-to-RouterOS BGP sessions ESTABLISHED
- [ ] OSPF adjacencies stable
- [ ] New loopback addresses configured on all nodes
- [ ] Old loopback addresses still present (dual addressing)
- [ ] VM connectivity unchanged (test VMs at fd00:101::6, fd00:101::7)
- [ ] DNS resolution working (fd00:0:0:ffff::53)
- [ ] NTP synchronization working

## Rollback Procedure

If issues occur during deployment:

```bash
# Revert to main branch configurations
git checkout main

# Redeploy original configuration
ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-frr.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini

ansible-playbook ansible/lae.proxmox/playbooks/stage2-configure-network.yml \
  -i ansible/lae.proxmox/inventory/hosts.ini

# Verify BGP sessions re-establish with old addresses
ssh root@pve01 "vtysh -c 'show bgp summary'"
```

**Note**: Because dual addressing is used, old addresses remain functional even after new config is deployed. Simply removing the new BGP neighbor configurations and rebooting FRR will revert to old behavior.

## Post-Deployment: Remove Old Addresses

**Only after Phase 1 is fully verified and stable**, create a follow-up commit to remove old addresses:

1. Edit `ansible/lae.proxmox/roles/interfaces/templates/interfaces.pve.j2`:
   - Remove line 133: `address fd00:255::{{ node_id }}/128`

2. Update RouterOS:
   - Remove old IPv4: `10.255.255.254`
   - Remove old IPv6: `fd00:255::fffe`

3. Commit and deploy removal

## Known Issues & Notes

- **Dual addressing**: Both old and new addresses are configured during transition
- **RouterOS manual config**: RouterOS updates must be done manually
- **VM loopbacks unchanged**: Phase 1 only updates infrastructure; VM loopbacks (Phase 2) come later
- **Static Anycast LLA unchanged**: Phase 3 will update `fe80::101:1` → `fe80::101:fffe`

## Next Phases

After Phase 1 is verified and old addresses removed:

- **Phase 2**: VM/K8s loopback addressing
  - `fd00:255:101::/64` → `fd00:101:fe::/64` (IPv6)
  - `10.255.101.0/24` → `10.101.254.0/24` (IPv4)

- **Phase 3**: Static Anycast LLA
  - `fe80::101:1` → `fe80::101:fffe`

- **Phase 4**: Documentation and cleanup

## Support Information

- **Plan file**: `/Users/sulibot/.claude/plans/smooth-fluttering-river.md`
- **Documentation**: `docs/ip-addressing-layout-2.md`
- **RouterOS guide**: `docs/PHASE1_ROUTEROS_CONFIG.md`
- **Branch**: `ip-renumber-phase1`
- **Commit**: `e1009fba`

---

*Generated during Phase 1 implementation - 2025-12-28*
