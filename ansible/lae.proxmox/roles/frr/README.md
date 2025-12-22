# FRR Role - Proxmox SDN Separation Safeguards

## Overview

This FRR role implements upgrade-safe safeguards to ensure **Proxmox SDN can NEVER manage FRR configuration**, even after Proxmox upgrades or SDN operations.

## Ownership Policy

- **FRR (Ansible-managed)**: All routing and control-plane logic
  - IS-IS underlay IGP
  - iBGP peering (loopback-to-loopback)
  - EVPN control plane (L2VPN address-family)
  - VRF configuration and BGP contexts
  - Anycast gateways (IRB interfaces)
  - eBGP to RouterOS (north/south routing)
  - All routing policy (route-maps, prefix-lists)

- **Proxmox SDN**: L2/VXLAN infrastructure ONLY
  - VRF device creation (`vrf_evpnz1`)
  - VXLAN interface creation (`vxlan_vnet*`)
  - Bridge device creation (`vnet*`)
  - VM attachment to tenant networks

- **Strictly Prohibited**:
  - Proxmox SDN modifying `/etc/frr/frr.conf`
  - `frr@sdn.service` being enabled or running
  - Any external modification to FRR configuration

## Implemented Safeguards

### 1. Service Masking (Upgrade-Safe)

**Task**: `Mask frr@sdn.service to prevent SDN from managing FRR`

Creates systemd mask: `/etc/systemd/system/frr@sdn.service → /dev/null`

- **Why masking vs disabling?**
  - `disabled`: Can be enabled by dependencies or upgrades
  - `masked`: Cannot be started even manually, survives upgrades

- **Effect**: Proxmox SDN controller object can exist (needed for VRF/VXLAN creation), but the service that writes FRR config is permanently disabled

### 2. Pre-Flight Service Check

**Task**: `Check if frr@sdn.service exists and is running`

Verifies service state before proceeding. Fails loudly if service is active with actionable error message.

### 3. Configuration Hash Verification (Tripwire)

**Tasks**:
- `Generate SHA256 hash of current FRR configuration`
- `Read stored configuration hash`
- `Verify FRR configuration has not been modified externally`
- `Save configuration hash to tripwire file`

**Mechanism**:
1. Before deploying config, compute SHA256 hash of existing `/etc/frr/frr.conf`
2. Compare with stored hash in `/etc/frr/.frr.conf.ansible-hash`
3. If mismatch detected → WARN (but continue to restore config)
4. After deploying config, save new hash for next run

**Benefits**:
- Detects any external modification (SDN, manual, upgrade scripts)
- Provides forensic evidence of configuration drift
- Self-healing: Playbook restores correct config automatically

### 4. Configuration Header Warning

Added to `frr-pve.conf.j2` template:

```
! ======================================================================
! FRR CONFIGURATION - ANSIBLE MANAGED
! ======================================================================
! WARNING: This file is EXCLUSIVELY managed by Ansible.
!          DO NOT modify manually or via Proxmox SDN.
!          Changes will be overwritten on next Ansible run.
!
! Ownership Policy:
!   - FRR: All routing and control-plane logic (IS-IS, BGP, EVPN, VRFs)
!   - Proxmox SDN: L2/VXLAN/VRF device plumbing ONLY
!   - frr@sdn.service: MUST be masked (never enabled, even after upgrades)
!
! Generated: <timestamp>
! Template: ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2
! Node: <hostname>
! ======================================================================
```

## Task Execution Order

1. **Pre-flight checks**:
   - Check if `frr@sdn.service` is running → FAIL if active
   - Mask `frr@sdn.service` → Prevents future activation

2. **Configuration integrity**:
   - Check if `frr.conf` exists
   - Compute current hash
   - Read stored hash
   - Verify hash matches → WARN if mismatch (but continue)

3. **System configuration**:
   - Enable VRF TCP accept sysctl

4. **FRR deployment**:
   - Deploy daemons configuration
   - Deploy frr.conf (Ansible template)
   - Compute new hash
   - Store hash to tripwire file

5. **Service management**:
   - Restart and enable `frr.service`

## Verification Commands

### Verify service is masked
```bash
systemctl status frr@sdn.service
# Should show: "Loaded: masked (Reason: Unit frr@sdn.service is masked.)"
```

### Verify hash file exists
```bash
cat /etc/frr/.frr.conf.ansible-hash
# Should show: SHA256 hash string
```

### Manually verify hash
```bash
sha256sum /etc/frr/frr.conf
cat /etc/frr/.frr.conf.ansible-hash
# Hashes should match
```

### Check configuration header
```bash
head -20 /etc/frr/frr.conf
# Should show Ansible ownership warning
```

## Testing Scenarios

### Test 1: Initial Deployment
```bash
ansible-playbook <playbook> --tags frr
```

Expected:
- `frr@sdn.service` becomes masked
- `/etc/frr/.frr.conf.ansible-hash` created
- FRR configuration deployed
- All tasks show "ok" or "changed"

### Test 2: Hash Verification
```bash
# Manually modify config
echo "! test modification" >> /etc/frr/frr.conf

# Re-run playbook
ansible-playbook <playbook> --tags frr
```

Expected:
- Task "Verify FRR configuration has not been modified externally" shows WARNING
- Playbook continues and restores correct configuration
- Hash file updated with new hash

### Test 3: Upgrade Simulation
```bash
# Simulate upgrade re-enabling service
systemctl unmask frr@sdn.service
systemctl start frr@sdn.service

# Re-run playbook
ansible-playbook <playbook> --tags frr
```

Expected:
- Task "Fail if frr@sdn.service is running" fails with error
- Follow remediation steps in error message
- Re-run playbook after manual intervention

### Test 4: Idempotency
```bash
# Run playbook twice
ansible-playbook <playbook> --tags frr
ansible-playbook <playbook> --tags frr
```

Expected:
- Second run shows all tasks as "ok" (no changes)
- Hash verification passes silently
- No warnings or failures

## Failure Modes

### If `frr@sdn.service` is running:
```
CRITICAL: frr@sdn.service is running!
This service MUST be masked to prevent SDN from managing FRR.

Immediate action required:
  systemctl stop frr@sdn.service
  systemctl mask frr@sdn.service

Re-run this playbook after masking the service.
```

**Resolution**: Follow commands in error message, then re-run playbook.

### If configuration hash mismatch:
```
============================================================================
CRITICAL: /etc/frr/frr.conf has been modified externally!
============================================================================
This violates the FRR ownership policy.

Expected hash: <stored_hash>
Current hash:  <actual_hash>

Possible causes:
  - Proxmox SDN modified FRR configuration
  - frr@sdn.service was enabled/started
  - Manual modification outside Ansible
  - Proxmox upgrade re-enabled SDN → FRR integration

Action required:
  1. Investigate what modified the file
  2. Re-run this playbook to restore correct configuration
  3. Verify frr@sdn.service is masked

The playbook will now restore the Ansible-managed configuration.
============================================================================
```

**Resolution**:
1. Investigate cause of modification (check logs, service status)
2. Playbook automatically restores correct config (self-healing)
3. Verify safeguards are in place after playbook completes

## Files

- **`tasks/main.yaml`**: Role tasks with safeguards
- **`templates/frr-pve.conf.j2`**: FRR configuration template with ownership header
- **`templates/daemons-pve.j2`**: FRR daemons configuration
- **`handlers/main.yaml`**: FRR service restart handler
- **`README.md`**: This file

## Notes

- **Hash file location**: `/etc/frr/.frr.conf.ansible-hash` (hidden file)
- **Hash algorithm**: SHA256
- **Masking persistence**: Survives reboots and upgrades
- **Self-healing**: Hash mismatch triggers warning but config is restored automatically
- **Tag support**: All safeguard tasks tagged with `frr` for selective execution

## Maintenance

### To intentionally modify FRR config:
1. Edit Ansible template: `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`
2. Run playbook: `ansible-playbook <playbook> --tags frr`
3. Hash is automatically updated after deployment

### To temporarily bypass safeguards (NOT RECOMMENDED):
```bash
# Skip hash verification (still masks service)
ansible-playbook <playbook> --tags frr --skip-tags hash-check
```

### To check safeguard status:
```bash
# Check all nodes in parallel
ansible pve -m shell -a "systemctl is-masked frr@sdn.service"
ansible pve -m shell -a "test -f /etc/frr/.frr.conf.ansible-hash && echo 'Hash file exists' || echo 'Hash file missing'"
```

## Architecture Decision

**Why not use `chattr +i` (immutable flag)?**
- FRR itself may need to write to config during runtime operations
- Immutable flag would break FRR's own config management
- Hash verification provides same protection without blocking legitimate writes

**Why `ignore_errors: true` on hash verification?**
- Allows playbook to continue and restore correct configuration
- Provides self-healing behavior
- Warning is still shown to alert operator
- Manual intervention only needed if service is running

**Why mask instead of disable?**
- Masking is upgrade-safe (symlink to `/dev/null`)
- Cannot be re-enabled by package dependencies
- Cannot be started even manually
- Provides strongest guarantee against accidental activation
