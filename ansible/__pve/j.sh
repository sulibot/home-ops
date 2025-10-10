#!/usr/bin/env bash
set -euo pipefail

# Base playbook
cat > wipe-ceph-devices.yml << 'EOF'
---
- name: Wipe OSD devices for Ceph
  hosts: pve
  become: true
  gather_facts: true

  roles:
    - wipe_ceph_devices
EOF

# Role directory structure
ROLE_DIR=roles/wipe_ceph_devices
mkdir -p \
  "${ROLE_DIR}/tasks" \
  "${ROLE_DIR}/defaults" \
  "${ROLE_DIR}/meta"

# tasks/main.yml
cat > "${ROLE_DIR}/tasks/main.yml" << 'EOF'
---
# tasks file for wipe_ceph_devices

- name: Wipe any existing filesystem signatures
  community.general.wipefs:
    device: "{{ item }}"
    force: yes
  loop: "{{ pve_ceph_osds }}"

- name: Zero first MiB on devices that still have partitions
  command: dd if=/dev/zero of={{ item }} bs=1M count=1
  args:
    warn: false
  loop: "{{ pve_ceph_osds }}"
  when: >
    (ansible_facts.devices[item | basename].partitions | default([])) | length > 0
EOF

# defaults/main.yml
cat > "${ROLE_DIR}/defaults/main.yml" << 'EOF'
---
# No defaults to override; we expect pve_ceph_osds in host_vars/group_vars
EOF

# meta/main.yml
cat > "${ROLE_DIR}/meta/main.yml" << 'EOF'
---
galaxy_info:
  author: yourname
  description: Wipe disks so Ceph can provision fresh OSDs
  license: MIT
  min_ansible_version: 2.9
  platforms:
    - name: Debian
      versions: all
    - name: Ubuntu
      versions: all

dependencies: []

collections:
  - community.general
EOF

echo "Scaffold complete!  Run:"
echo "  ansible-playbook -i inventory/hosts.ini wipe-ceph-devices.yml"

