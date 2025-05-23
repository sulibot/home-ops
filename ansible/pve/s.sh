#!/usr/bin/env bash

# This script scaffolds the Ansible playbook and roles layout for a Proxmox+Ceph cluster
# Run from the root of your repository

set -euo pipefail

# Create directory structure
mkdir -p \
  group_vars \
  roles/bootstrap/{defaults,tasks,handlers,meta,files,templates} \
  roles/ceph-cluster/{defaults,tasks,handlers,meta,files,templates} \
  roles/ceph-crush/{defaults,tasks,handlers,meta,files,templates} \
  roles/pve-config/{defaults,tasks,handlers,meta,files,templates} \
  roles/zed/{defaults,tasks,handlers,meta,files,templates} \
  roles/certbot/{defaults,tasks,handlers,meta,templates}

# site.yml
cat > site.yml << 'EOF'
---
# playbooks/site.yml
- hosts: pve
  become: true

  vars_files:
    - group_vars/pve.yml

  roles:
    - bootstrap
    - ceph-cluster
    - ceph-crush
    - pve-config
    - zed
    - certbot
EOF

# group_vars/pve.yml
cat > group_vars/pve.yml << 'EOF'
# group_vars/pve.yml

# Ceph CSI pool definitions
ceph_csi_pools:
  - name: rbd
    pg_num: 128
    type: replicated
    rule: replicated_rule
  - name: cephfs_data
    pg_num: 128
    type: erasure
    rule_id: 3

# CephFS filesystems
ceph_csi_fs:
  - name: kubernetes
    metadata_pool: kubernetes_metadata
    data_pool: kubernetes_data
  - name: data
    metadata_pool: content_metadata
    data_pool: content_data

# CSI CephX clients
ceph_csi_clients:
  client.kubernetes:
    entity: client.kubernetes
    caps:
      mon: 'profile rbd'
      osd: 'profile rbd'
  client.content:
    entity: client.content
    caps:
      mon: 'profile rbd'
      osd: 'profile rbd'

# CephFS subvolume groups & static subvolumes
ceph_csi_subvol_groups:
  - fs: kubernetes
    group: csi
  - fs: data
    group: content

ceph_csi_static_subvols:
  - fs: data
    subvol: media
    group: content

# Certbot/Cloudflare settings
certbot_email: you@sulibot.com
cloudflare_api_key: YOUR_CLOUDFLARE_API_KEY
pve_cert_domains:
  - pve01.sulibot.com
  - pve02.sulibot.com
  - pve03.sulibot.com
EOF

# roles/bootstrap/tasks/main.yml
cat > roles/bootstrap/tasks/main.yml << 'EOF'
---
# roles/bootstrap/tasks/main.yml

# Repositories & GPG keys
- name: Remove any enterprise or Ceph-Quincy list files
  file:
    path: "{{ item }}"
    state: absent
  loop:
    - /etc/apt/sources.list.d/pve-enterprise.list
    - /etc/apt/sources.list.d/ceph.list
    - /etc/apt/sources.list.d/ceph-quincy.list

- name: Comment out enterprise lines in /etc/apt/sources.list
  replace:
    path: /etc/apt/sources.list
    regexp: '^(deb .*enterprise\.proxmox\.com.*|deb .*ceph-quincy.*)$'
    replace: '# \0'

- name: Add PVE no-subscription repo
  apt_repository:
    filename: pve-no-subscription
    repo: "deb http://download.proxmox.com/debian/pve {{ ansible_distribution_release }} pve-no-subscription"
    state: present

- name: Install Proxmox VE release GPG key
  apt_key:
    url: "https://enterprise.proxmox.com/debian/proxmox-release-{{ ansible_distribution_release }}.gpg"
    state: present

- name: Add Ceph-Squid repo
  apt_repository:
    filename: ceph-squid
    repo: "deb http://download.proxmox.com/debian/ceph-squid {{ ansible_distribution_release }} no-subscription"
    state: present

- name: Update apt cache
  apt:
    update_cache: yes

# Terraform support
- name: Create Terraform user if missing
  shell: |
    if ! pveum user list | grep -qw 'terraform@pve'; then
      pveum user add terraform@pve
    fi
  run_once: true

- name: Create Terraform role if missing
  shell: |
    if ! pveum role list | grep -qw 'Terraform'; then
      pveum role add Terraform \
        -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate  \
        Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use \
        VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit \
        VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory \
        VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor \
        VM.PowerMgmt User.Modify"
    fi
  run_once: true

- name: Assign Terraform role to user
  shell: |
    if ! pveum acl list / | grep -E "terraform@pve.*Terraform"; then
      pveum aclmod / -user terraform@pve -role Terraform
    fi
  run_once: true

- name: Create Terraform API token if missing
  shell: |
    if ! pveum user token list terraform@pve | grep -qw provider; then
      pveum user token add terraform@pve provider --privsep=0
    fi
  register: tf_token
  run_once: true
EOF

# roles/bootstrap/defaults/main.yml
cat > roles/bootstrap/defaults/main.yml << 'EOF'
---
# roles/bootstrap/defaults/main.yml
# No defaults defined here
EOF

# roles/bootstrap/handlers/main.yml
cat > roles/bootstrap/handlers/main.yml << 'EOF'
---
# roles/bootstrap/handlers/main.yml
- name: restart apt-daily
  service:
    name: apt-daily.service
    state: restarted
EOF

# roles/bootstrap/meta/main.yml
cat > roles/bootstrap/meta/main.yml << 'EOF'
---
# roles/bootstrap/meta/main.yml
dependencies: []
EOF

# roles/ceph-cluster/tasks/main.yml
cat > roles/ceph-cluster/tasks/main.yml << 'EOF'
---
# roles/ceph-cluster/tasks/main.yml

- name: Create CSI Ceph pools
  ceph.automation.ceph_pool:
    cluster: ceph
    name: "{{ item.name }}"
    pg_num: "{{ item.pg_num }}"
    pgp_num: "{{ item.pg_num }}"
    state: present
    type: "{{ item.type }}"
    crush_ruleset: "{{ item.rule_id | default(item.rule) }}"
  loop: "{{ ceph_csi_pools }}"

- name: Create CephFS filesystems
  ceph.automation.ceph_fs:
    cluster: ceph
    name: "{{ item.name }}"
    metadata_pool: "{{ item.metadata_pool }}"
    data_pool: "{{ item.data_pool }}"
    state: present
  loop: "{{ ceph_csi_fs }}"

- name: Create CSI CephX client keys
  ceph.automation.ceph_key:
    cluster: ceph
    key_name: "{{ item.entity }}"
    caps: "{{ item.caps }}"
    state: present
    dest: "/etc/ceph/{{ item.entity }}.keyring"
  loop: "{{ ceph_csi_clients.values() | list }}"

- name: Create CephFS subvolume groups
  command: >-
    ceph fs subvolume group create {{ item.fs }} {{ item.group }}
  loop: "{{ ceph_csi_subvol_groups }}"

- name: Create static PV subvolumes
  command: >-
    ceph fs subvolume create {{ item.fs }} {{ item.subvol }} --group {{ item.group }}
  loop: "{{ ceph_csi_static_subvols }}"
EOF

# roles/ceph-cluster/defaults/main.yml
cat > roles/ceph-cluster/defaults/main.yml << 'EOF'
---
# roles/ceph-cluster/defaults/main.yml
# No defaults defined here
EOF

# roles/ceph-cluster/handlers/main.yml
cat > roles/ceph-cluster/handlers/main.yml << 'EOF'
---
# roles/ceph-cluster/handlers/main.yml
- name: restart ceph-mgr
  command: ceph mgr module enable dashboard
EOF

# roles/ceph-cluster/meta/main.yml
cat > roles/ceph-cluster/meta/main.yml << 'EOF'
---
# roles/ceph-cluster/meta/main.yml
collections:
  - ceph.automation
EOF

# roles/ceph-crush/tasks/main.yml
cat > roles/ceph-crush/tasks/main.yml << 'EOF'
---
# roles/ceph-crush/tasks/main.yml

- name: Install Ceph crush tools (crushtool)
  apt:
    name: ceph-base
    state: present
    update_cache: yes

- name: Copy CRUSH map
  copy:
    src: "{{ playbook_dir }}/../{{ pve_ceph_custom_crushmap }}"
    dest: /tmp/crushmap.txt

- name: Compile CRUSH map
  command: crushtool -c /tmp/crushmap.txt -o /tmp/crushmap.bin

- name: Apply CRUSH map
  command: ceph osd setcrushmap -i /tmp/crushmap.bin
EOF

# roles/ceph-crush/defaults/main.yml
cat > roles/ceph-crush/defaults/main.yml << 'EOF'
---
# roles/ceph-crush/defaults/main.yml
# No defaults defined here
EOF

# roles/ceph-crush/handlers/main.yml
cat > roles/ceph-crush/handlers/main.yml << 'EOF'
---
# roles/ceph-crush/handlers/main.yml
- name: cleanup tmp crush files
  file:
    path: /tmp/crushmap.*
    state: absent
EOF

# roles/ceph-crush/meta/main.yml
cat > roles/ceph-crush/meta/main.yml << 'EOF'
---
# roles/ceph-crush/meta/main.yml
dependencies:
  - ceph-cluster
EOF

# roles/pve-config/tasks/main.yml
cat > roles/pve-config/tasks/main.yml << 'EOF'
---
# roles/pve-config/tasks/main.yml

- name: Add Ceph RBD storage via pvesh
  command: >-
    pvesh set /storage/rbd
      --type rbd
      --pool rbd
      --content images,rootdir,backup
      --monhost {{ groups.pve | map('extract',hostvars,'ansible_host') | join(',') }}
      --nodes {{ groups.pve | join(',') }}
  become: true

- name: Add CephFS storage via pvesh
  command: >-
    pvesh set /storage/cephfs
      --type cephfs
      --export data
      --content iso,vztmpl,rootdir
      --path /mnt/pve/cephfs
      --nodes {{ groups.pve | join(',') }}
  become: true

- name: Disable PVE subscription nag
  command: pvesh set /datacenter/config --no-subscription true
  args:
    warn: false

- name: Set Datacenter DNS servers
  command: pvesh set /datacenter/config --dns fd00:255::fffe,10.255.255.254
  args:
    warn: false

- name: Ensure /etc/hosts has PVE entries
  lineinfile:
    path: /etc/hosts
    create: yes
    line: "{{ item }}"
  loop:
    - "fc00:255::1   pve01"
    - "fc00:255::2   pve02"
    - "fc00:255::3   pve03"

- name: Ensure pve-cluster service is running
  service:
    name: pve-cluster
    state: started
    enabled: true

- name: Ensure pvestatd service is running
  service:
    name: pvestatd
    state: started
    enabled: true
EOF

# roles/pve-config/defaults/main.yml
cat > roles/pve-config/defaults/main.yml << 'EOF'
---
# roles/pve-config/defaults/main.yml
# No defaults defined here
EOF

# roles/pve-config/handlers/main.yml
cat > roles/pve-config/handlers/main.yml << 'EOF'
---
# roles/pve-config/handlers/main.yml
- name: restart pveproxy
  service:
    name: pveproxy
    state: restarted
EOF

# roles/pve-config/meta/main.yml
cat > roles/pve-config/meta/main.yml << 'EOF'
---
# roles/pve-config/meta/main.yml
dependencies:
  - bootstrap
EOF

# roles/zed/tasks/main.yml
cat > roles/zed/tasks/main.yml << 'EOF'
---
# roles/zed/tasks/main.yml

- name: Install ssmtp and ZFS utilities
  apt:
    name:
      - ssmtp
      - zfsutils-linux
    state: present
    update_cache: yes

- name: Configure ssmtp for mail
  copy:
    dest: /etc/ssmtp/ssmtp.conf
    content: |-
      root=postmaster
      mailhub=smtp.sulibot.com:587
      AuthUser=you@sulibot.com
      AuthPass=supersecret
      FromLineOverride=YES
    mode: '0600'

- name: Load ZFS kernel module
  modprobe:
    name: zfs
  ignore_errors: true

- name: Configure ZED email address
  lineinfile:
    path: /etc/zfs/zed.d/zed.rc
    regexp: '^MAILADDR='
    line: 'MAILADDR="sulibot@gmail.com"'
    create: yes

- name: Ensure ZED service is running
  service:
    name: zed
    state: started
    enabled: true
EOF

# roles/zed/defaults/main.yml
cat > roles/zed/defaults/main.yml << 'EOF'
---
# roles/zed/defaults/main.yml
# No defaults defined here
EOF

# roles/zed/handlers/main.yml
cat > roles/zed/handlers/main.yml << 'EOF'
---
# roles/zed/handlers/main.yml
- name: restart zed
  service:
    name: zed
    state: restarted
EOF

# roles/zed/meta/main.yml
cat > roles/zed/meta/main.yml << 'EOF'
---
# roles/zed/meta/main.yml
dependencies:
  - pve-config
EOF

# roles/certbot/tasks/main.yml
cat > roles/certbot/tasks/main.yml << 'EOF'
---
# roles/certbot/tasks/main.yml

- name: Install certbot and Cloudflare plugin
  apt:
    name:
      - certbot
      - python3-certbot-dns-cloudflare
    state: present
    update_cache: yes

- name: Deploy Cloudflare credentials for Certbot
  template:
    src: cloudflare.ini.j2
    dest: /etc/letsencrypt/cloudflare.ini
    mode: '0600'

- name: Obtain Let's Encrypt certificate for PVE hosts
  command: >-
    certbot certonly \
      --dns-cloudflare \
      --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
      --agree-tos --non-interactive \
      --email {{ certbot_email }} \
      {% for d in pve_cert_domains %}-d {{ d }} {% endfor %}
  args:
    creates: "/etc/letsencrypt/live/{{ pve_cert_domains[0] }}/fullchain.pem"

- name: Deploy PVE SSL certificate
  copy:
    src: "/etc/letsencrypt/live/{{ pve_cert_domains[0] }}/fullchain.pem"
    dest: /etc/pve/local/pve-ssl.pem
    mode: '0644'

- name: Deploy PVE SSL private key
  copy:
    src: "/etc/letsencrypt/live/{{ pve_cert_domains[0] }}/privkey.pem"
    dest: /etc/pve/local/pve-ssl.key
    mode: '0600'

- name: Restart pveproxy to apply new certificates
  service:
    name: pveproxy
    state: restarted
EOF

# roles/certbot/defaults/main.yml
cat > roles/certbot/defaults/main.yml << 'EOF'
---
# roles/certbot/defaults/main.yml
# No defaults defined here
EOF

# roles/certbot/handlers/main.yml
cat > roles/certbot/handlers/main.yml << 'EOF'
---
# roles/certbot/handlers/main.yml
- name: restart pveproxy
  service:
    name: pveproxy
    state: restarted
EOF

# roles/certbot/meta/main.yml
cat > roles/certbot/meta/main.yml << 'EOF'
---
# roles/certbot/meta/main.yml
dependencies:
  - pve-config
EOF

# roles/certbot/templates/cloudflare.ini.j2
cat > roles/certbot/templates/cloudflare.ini.j2 << 'EOF'
# Cloudflare API credentials for Certbot
# Replace these placeholders in group_vars/pve.yml

dns_cloudflare_email = {{ certbot_email }}
dns_cloudflare_api_key = {{ cloudflare_api_key }}
EOF

chmod +x create_ansible_structure.sh

echo "Scaffolded Ansible structure successfully."
