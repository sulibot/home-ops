#!/usr/bin/env bash
set -euo pipefail

###
### 1) Create the wipe_ceph_devices role
###
mkdir -p roles/wipe_ceph_devices/{tasks,defaults,meta}

cat > roles/wipe_ceph_devices/tasks/main.yml << 'EOF'
---
# roles/wipe_ceph_devices/tasks/main.yml

- name: "Gather list of all OSD devices"
  set_fact:
    all_osd_devs: "{{ ceph_osd_map | map(attribute='dev') | list }}"

- name: "Partition each HDD into two equal halves"
  parted:
    device: "{{ item.drive }}"
    label: gpt
  loop: "{{ all_osd_devs
            | select('search','^/dev/sd')
            | map('regex_replace','([0-9]+)$','')
            | unique
            | list }}"
  loop_control:
    label: "{{ item }}"

- name: "Create half-disk partitions (0–50%, 50–100%)"
  parted:
    device: "{{ item.drive }}"
    number: "{{ item.number }}"
    state: present
    part_start: "{{ item.start }}"
    part_end: "{{ item.end }}"
    unit: '%'
  loop: |
    {% for d in all_osd_devs
         | select('search','^/dev/sd')
         | map('regex_replace','([0-9]+)$','')
         | unique %}
    - { drive: "{{ d }}", number: 1, start: 0%,   end: 50% }
    - { drive: "{{ d }}", number: 2, start: 50%,  end: 100% }
    {% endfor %}

- name: "Wipe Ceph metadata from all OSD devices"
  community.general.wipefs:
    device: "{{ item }}"
    force: yes
  loop: "{{ all_osd_devs }}"

- name: "Zero out first MiB to remove any leftover signatures"
  command: dd if=/dev/zero of={{ item }} bs=1M count=1
  args:
    warn: false
  loop: "{{ all_osd_devs }}"
EOF

cat > roles/wipe_ceph_devices/defaults/main.yml << 'EOF'
---
# No defaults needed; uses ceph_osd_map from host_vars
EOF

cat > roles/wipe_ceph_devices/meta/main.yml << 'EOF'
---
galaxy_info:
  author: you
  description: Partition & wipe OSD devices ahead of provisioning
  license: MIT
  min_ansible_version: 2.9
  platforms:
    - name: Debian
      versions: all
    - name: Ubuntu
      versions: all
collections:
  - community.general
dependencies: []
EOF

###
### 2) Create a standalone playbook for wiping
###
cat > playbooks/wipe-osds.yml << 'EOF'
---
- name: Partition & wipe all OSD devices
  hosts: pve
  become: true
  gather_facts: true

  roles:
    - wipe_ceph_devices
EOF

###
### 3) Create/Update the ceph-init role for provisioning only
###
mkdir -p roles/ceph-init/{tasks,defaults,meta}

cat > roles/ceph-init/tasks/main.yml << 'EOF'
---
# roles/ceph-init/tasks/main.yml

- name: Assert Ceph network vars are set
  assert:
    that:
      - pve_ceph_network is defined
      - pve_ceph_cluster_network is defined
    fail_msg: "Missing Ceph network variables"
  when: inventory_hostname == groups['pve'][0]

- name: Install Proxmox-Ceph packages
  apt:
    name:
      - ceph-mon
      - ceph-mgr
      - ceph-common
      - ceph-mds  # if you need CephFS
    state: present
    update_cache: yes

- name: Initialize Ceph on bootstrap node
  command: >
    pveceph init
      --network {{ pve_ceph_network }}
      --cluster-network {{ pve_ceph_cluster_network }}
  args:
    creates: /etc/pve/ceph.conf
  when: inventory_hostname == groups['pve'][0]

- name: Render full ceph.conf on bootstrap
  template:
    src: ceph.conf.j2
    dest: /etc/pve/ceph.conf
    owner: root
    group: www-data
    mode: '0640'
  notify: Reload Ceph mons
  when: inventory_hostname == groups['pve'][0]

- name: Wait for ceph.conf on secondaries
  wait_for:
    path: /etc/pve/ceph.conf
    timeout: 300
  when: inventory_hostname != groups['pve'][0]

- name: Create Ceph monitor on secondary nodes
  command: pveceph mon create
  args:
    creates: /var/lib/ceph/mon/ceph-{{ inventory_hostname }}
  register: mon
  failed_when: mon.rc not in [0] and "'already in use'" not in mon.stderr
  changed_when: mon.rc == 0
  when: inventory_hostname != groups['pve'][0]

- name: Create Ceph manager daemon
  command: pveceph mgr create
  args:
    creates: /var/lib/ceph/mgr/ceph-{{ inventory_hostname }}

- name: Provision OSDs in CRUSH-map order
  command: pveceph osd create {{ item.dev }}
  args:
    creates: "/var/lib/ceph/osd/ceph-{{ item.id }}"
  register: out
  failed_when: out.rc not in [0,25]  # 25 = “already in use”
  changed_when: out.rc == 0
  loop: "{{ ceph_osd_map }}"
  loop_control:
    label: "{{ item.id }} → {{ item.dev }}"
EOF

cat > roles/ceph-init/defaults/main.yml << 'EOF'
---
# roles/ceph-init/defaults/main.yml
pve_ceph_network: "fc00:20::/64"
pve_ceph_cluster_network: "fc00:21::/64"
EOF

cat > roles/ceph-init/meta/main.yml << 'EOF'
---
dependencies:
  - bootstrap
EOF

###
### 4) Write inventory/host_vars for each node (with proper YAML syntax)
###
mkdir -p inventory/host_vars

cat > inventory/host_vars/pve01.yml << 'EOF'
---
ceph_osd_map:
  - id:  0;  dev: /dev/nvme1n1;  class: nvme
  - id:  3;  dev: /dev/sda1;     class: hdd
  - id:  4;  dev: /dev/sda2;     class: hdd
  - id:  5;  dev: /dev/sdb1;     class: hdd
  - id:  6;  dev: /dev/sdb2;     class: hdd
  - id:  7;  dev: /dev/sdc1;     class: hdd
  - id:  8;  dev: /dev/sdc2;     class: hdd
EOF

cat > inventory/host_vars/pve02.yml << 'EOF'
---
ceph_osd_map:
  - id:  1;  dev: /dev/nvme1n1;  class: nvme
  - id:  9;  dev: /dev/sda1;     class: hdd
  - id: 10;  dev: /dev/sda2;     class: hdd
  - id: 11;  dev: /dev/sdb1;     class: hdd
  - id: 12;  dev: /dev/sdb2;     class: hdd
  - id: 13;  dev: /dev/sdc1;     class: hdd
  - id: 14;  dev: /dev/sdc2;     class: hdd
EOF

cat > inventory/host_vars/pve03.yml << 'EOF'
---
ceph_osd_map:
  - id:  2;  dev: /dev/nvme1n1;  class: nvme
  - id: 15;  dev: /dev/sda1;     class: hdd
  - id: 16;  dev: /dev/sda2;     class: hdd
  - id: 17;  dev: /dev/sdb1;     class: hdd
  - id: 18;  dev: /dev/sdb2;     class: hdd
  - id: 19;  dev: /dev/sdc1;     class: hdd
  - id: 20;  dev: /dev/sdc2;     class: hdd
EOF

echo "✅ Done.  
→ To *wipe* disks:  
    ansible-playbook -i inventory/hosts.ini playbooks/wipe-osds.yml  

→ Then to *provision* Ceph:  
    ansible-playbook -i inventory/hosts.ini playbooks/site.yml  
"
