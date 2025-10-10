#!/usr/bin/env bash
set -euo pipefail

# 1) Create per-node OSD mapping under inventory/host_vars
mkdir -p inventory/host_vars
cat > inventory/host_vars/pve01.yml << 'EOF'
pve_ceph_osd_map:
  0: /dev/nvme1n1
  3: /dev/sda1
  4: /dev/sda2
  5: /dev/sdb1
  6: /dev/sdb2
  7: /dev/sdc1
  8: /dev/sdc2
EOF

cat > inventory/host_vars/pve02.yml << 'EOF'
pve_ceph_osd_map:
  1: /dev/nvme1n1
  9: /dev/sda1
  10: /dev/sda2
  11: /dev/sdb1
  12: /dev/sdb2
  13: /dev/sdc1
  14: /dev/sdc2
EOF

cat > inventory/host_vars/pve03.yml << 'EOF'
pve_ceph_osd_map:
  2: /dev/nvme1n1
  15: /dev/sda1
  16: /dev/sda2
  17: /dev/sdb1
  18: /dev/sdb2
  19: /dev/sdc1
  20: /dev/sdc2
EOF

# 2) Create the new osd provisioning task file
mkdir -p roles/ceph-init/tasks
cat > roles/ceph-init/tasks/osd.yml << 'EOF'
# Provision OSDs in CRUSH-map order
- name: Provision OSDs in CRUSH-map order
  become: true
  vars:
    # Build a sorted list of {key,item.key,value,item.value}
    osd_items: |
      {{ pve_ceph_osd_map | dict2items | sort(attribute='key') }}
  loop: "{{ osd_items }}"
  loop_control:
    label: "osd.{{ item.key }} → {{ item.value }}"
  command: >
    pveceph osd create {{ item.value }}
  args:
    creates: "/var/lib/ceph/osd/ceph-{{ item.value | basename }}"
  register: provision_osd
  failed_when: provision_osd.rc not in [0, 1]
  changed_when: provision_osd.rc == 0
EOF

# 3) Instruct to import the new tasks file in main.yml
echo ""
echo "👉 Now update roles/ceph-init/tasks/main.yml to replace your old OSD creation block with:"
echo "   - import_tasks: osd.yml"
echo "   (place it where the previous provisioning step lived)"
