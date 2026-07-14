#!/bin/bash

ROLE_NAME="jool"

echo "Creating Ansible role directory structure for '$ROLE_NAME'..."

# Create the main role directory
mkdir -p "$ROLE_NAME"/{defaults,meta,tasks}

# Create defaults/main.yml
cat <<EOF > "$ROLE_NAME/defaults/main.yml"
---
# defaults file for jool
jool_version: "4.1.14"
jool_download_url: "https://github.com/NICMx/Jool/releases/download/v{{ jool_version }}"
jool_pool6_prefix: "64:ff9b:1::/96"
# Example system IP addresses (for informational purposes or other roles)
system_ipv4_address: "10.0.200.64"
system_ipv6_address: "fd00:200::64"
# DNS information is descriptive and typically configured outside this specific Jool role,
# but can be referenced here for context.
# DNS is served by RouterOS with Cloudflare DNS64 upstreams.
EOF

# Create meta/main.yml
cat <<EOF > "$ROLE_NAME/meta/main.yml"
---
# meta file for jool
galaxy_info:
  author: Your Name # Replace with your name
  description: An Ansible role to install and configure Jool for Stateful NAT64.
  license: MIT
  min_ansible_version: "2.10"
  platforms:
    - name: Ubuntu
      versions:
        - "20.04"
        - "22.04"
    - name: Debian
      versions:
        - "10"
        - "11"
        - "12" # Added Debian 12
        - "13" # Added Debian 13
  galaxy_tags:
    - networking
    - nat64
    - ipv6
    - jool
    - debian

dependencies: []
EOF

# Create tasks/main.yml
cat <<EOF > "$ROLE_NAME/tasks/main.yml"
---
- name: Ensure kernel headers are installed
  ansible.builtin.apt:
    name: "linux-headers-{{ ansible_kernel }}"
    state: present
    update_cache: yes
  tags:
    - install

- name: Download Jool DEB packages
  ansible.builtin.get_url:
    url: "{{ item }}"
    dest: "/tmp/"
    mode: '0644'
  loop:
    - "{{ jool_download_url }}/jool-dkms_{{ jool_version }}-1_all.deb"
    - "{{ jool_download_url }}/jool-tools_{{ jool_version }}-1_amd64.deb"
  tags:
    - install

- name: Install Jool DEB packages
  ansible.builtin.apt:
    deb: "{{ item }}"
  loop:
    - "/tmp/jool-dkms_{{ jool_version }}-1_all.deb"
    - "/tmp/jool-tools_{{ jool_version }}-1_amd64.deb"
  tags:
    - install

- name: Enable IPv4 forwarding
  ansible.posix.sysctl:
    name: net.ipv4.conf.all.forwarding
    value: '1'
    state: present
    reload: yes
  tags:
    - configure

- name: Enable IPv6 forwarding
  ansible.posix.sysctl:
    name: net.ipv6.conf.all.forwarding
    value: '1'
    state: present
    reload: yes
  tags:
    - configure

- name: Ensure Jool kernel module is loaded
  ansible.builtin.modprobe:
    name: jool
    state: present
  tags:
    - configure

- name: Add a Stateful NAT64 instance
  ansible.builtin.command: "jool instance add --netfilter --pool6 {{ jool_pool6_prefix }}"
  register: jool_instance_status
  failed_when: "'already exists' not in jool_instance_status.stderr and jool_instance_status.rc != 0"
  changed_when: "'already exists' not in jool_instance_status.stderr"
  tags:
    - configure
EOF

echo "Ansible role '$ROLE_NAME' created successfully in the current directory. 🎉"
echo "You can now navigate into the '$ROLE_NAME' directory and inspect the files."