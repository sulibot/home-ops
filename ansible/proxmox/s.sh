#!/usr/bin/env bash
set -euo pipefail

# Scaffold Ansible role and playbook to update Proxmox repositories and remove subscription nag

# Create role directory structure
mkdir -p roles/proxmox_repo/{defaults,tasks}
mkdir -p playbooks

# Default variables for the role
cat > roles/proxmox_repo/defaults/main.yml << 'EOF'
---
# Paths and definitions for Proxmox APT repos
proxmox_apt_sources:
  pve_enterprise: /etc/apt/sources.list.d/pve-enterprise.list
  pve_no_subscription:
    repo: 'deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription'
    filename: pve-no-subscription
  ceph_list: /etc/apt/sources.list.d/ceph.list
EOF

# Main tasks for disabling/enabling repos and removing nag
cat > roles/proxmox_repo/tasks/main.yml << 'EOF'
---
- name: Disable pve-enterprise repository
  file:
    path: "{{ proxmox_apt_sources.pve_enterprise }}"
    state: absent

- name: Enable pve-no-subscription repository
  ansible.builtin.apt_repository:
    repo: "{{ proxmox_apt_sources.pve_no_subscription.repo }}"
    filename: "{{ proxmox_apt_sources.pve_no_subscription.filename }}"
    state: present

- name: Correct Ceph package sources
  ansible.builtin.copy:
    dest: "{{ proxmox_apt_sources.ceph_list }}"
    content: |
      # deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
      # deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription
      # deb https://enterprise.proxmox.com/debian/ceph-reef bookworm enterprise
      # deb http://download.proxmox.com/debian/ceph-reef bookworm no-subscription
    mode: '0644'

- name: Remove Proxmox subscription nag screen
  ansible.builtin.copy:
    dest: /etc/apt/apt.conf.d/no-nag-script
    content: |
      DPkg::Post-Invoke { "dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib\.js$'; if [ $? -eq 1 ]; then { sed -i '/.*data\.status.*{/{s/\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; }; fi"; };
    mode: '0644'

- name: Reinstall proxmox‑widget‑toolkit to apply nag removal
  ansible.builtin.apt:
    name: proxmox-widget-toolkit
    state: latest

- name: Refresh APT cache
  ansible.builtin.apt:
    update_cache: yes
EOF

# Playbook to drive the new role
echo "---" > playbooks/post_pve_repo_update.yml
cat >> playbooks/post_pve_repo_update.yml << 'EOF'
- hosts: all
  become: true
  roles:
    - proxmox_repo
EOF

# Minimal Ansible configuration to pick up our roles
cat > ansible.cfg << 'EOF'
[defaults]
roles_path = ./roles
EOF

echo "Scaffold complete!  Run: ansible-playbook playbooks/post_pve_repo_update.yml"

