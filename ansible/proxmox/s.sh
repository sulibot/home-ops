#!/usr/bin/env bash
set -euo pipefail

echo "Creating playbook directory structure..."
mkdir -p playbooks

echo "Writing playbooks..."

# 1. Bootstrap network primitives
cat > playbooks/stage2-bootstrap-network.yml << 'EOF'
---
- name: Stage 2 - Bootstrap network primitives
  hosts: pve
  become: true
  roles:
    - role: pve_networking
EOF

# 2. Host configuration (chrony, sysctl, ssh, journald, fstrim)
cat > playbooks/stage2-host-configuration.yml << 'EOF'
---
- name: Stage 2 - Host configuration
  hosts: pve
  become: true
  roles:
    - role: post_pve_install
    - role: common       # chrony, base OS tuning
    - role: sysctl       # kernel parameters & forwarding
    - role: ssh_config   # PermitRootLogin, authorized_keys
    - role: journald     # persistent logs
    - role: fstrim       # periodic fstrim
    - role: swappiness   # vm.swappiness tuning
    - role: timezone     # UTC timezone
    - role: ssh_keys     # distribute root SSH keys
    - role: host_limits  # /etc/security limits
    - role: reboot_handler
    - role: os_updates
    - role: fail2ban     # optional
    - role: snmpd        # optional
    - role: node_exporter # optional
    - role: log_forwarding
    - role: zfs_tuning   # optional
EOF

# 3. Configure network interfaces
cat > playbooks/stage2-configure-network.yml << 'EOF'
---
- name: Stage 2 - Configure network interfaces
  hosts: pve
  become: true
  vars_files:
    - ../group_vars/all.yaml
    - ../group_vars/cluster.yaml
  roles:
    - role: interfaces
EOF

# 4. Configure FRR routing
cat > playbooks/stage2-configure-frr.yml << 'EOF'
---
- name: Stage 2 - Configure FRR routing
  hosts: pve
  become: true
  vars_files:
    - ../group_vars/all.yaml
  roles:
    - role: frr
EOF

# 5. Prepare Ceph disks (destructive)
cat > playbooks/stage2-prep-ceph-disks.yml << 'EOF'
---
- name: Stage 2 - Prepare Ceph OSD disks (DANGEROUS)
  hosts: ceph_osd
  become: true
  vars_prompt:
    - name: confirm_destruction
      prompt: "Type YES to confirm destructive disk wipe"
      private: no
  tasks:
    - name: Abort if not confirmed
      fail:
        msg: "Destructive action not confirmed. Exiting."
      when: confirm_destruction != 'YES'
  roles:
    - role: pve_ceph_disk_prep
EOF

echo "All playbooks created under ./playbooks"

