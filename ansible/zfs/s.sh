#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${1:-zfsbootmenu_pxe}"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# === Directory Structure ===
mkdir -p \
  roles/zfsbootmenu_http/tasks \
  roles/pxe_routeros/tasks \
  roles/tftp/tasks \
  templates \
  files \
  group_vars \
  host_vars

# === Inventory ===
cat > inventory.ini <<'EOF'
[all:vars]
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[pxe_servers:vars]
ansible_user=admin
ansible_network_os=routeros
ansible_connection=network_cli

[pxe_servers]
router1 ansible_host=10.0.9.254 ansible_password=<your-routeros-password>

[tftp_servers]
infraweb ansible_host=10.0.9.95

[infraweb]
infraweb ansible_host=infraweb.sulibot.com

[pve:vars]
ansible_user=root

[pve]
pve01 ansible_host=fd00:9::1 node_role=bootstrap ceph_role=mon,mgr,osd
pve02 ansible_host=fd00:9::2 node_role=standard ceph_role=mon,osd
pve03 ansible_host=fd00:9::3 node_role=standard ceph_role=mon,osd
pve04 ansible_host=fd00:9::4 node_role=standard ceph_role=none
EOF

# === Host Vars ===
cat > host_vars/pve01.yml <<'EOF'
proxmox_nic: enp4s0

proxmox_ipv4: 10.0.9.1
proxmox_ipv6: fd00:9::1
proxmox_ipv4_gw: 10.0.9.254
proxmox_ipv6_gw: fd00:9::fffe
proxmox_dns:
  - 10.0.9.254
  - fd00:9::fffe

optane_disk: /dev/disk/by-id/nvme-INTEL_SSDPE21D015TA_PHKE3425002P1P5CGN
nvme_disk: /dev/disk/by-id/nvme-Seagate_ZP2000GM30073_D36004PX

zfs_pool: rpool
zfs_root_partition_size_gb: 64
EOF

cat > host_vars/pve02.yml <<'EOF'
proxmox_nic: enp4s0

proxmox_ipv4: 10.0.9.2
proxmox_ipv6: fd00:9::2
proxmox_ipv4_gw: 10.0.9.254
proxmox_ipv6_gw: fd00:9::fffe
proxmox_dns:
  - 10.0.9.254
  - fd00:9::fffe

optane_disk: /dev/disk/by-id/nvme-INTEL_SSDPE21D015TA_PHKE335100J51P5CGN
nvme_disk: /dev/disk/by-id/nvme-Seagate_ZP2000GM30073_D360062PZ

zfs_pool: rpool
zfs_root_partition_size_gb: 64
EOF

cat > host_vars/pve03.yml <<'EOF'
proxmox_nic: enp4s0

proxmox_ipv4: 10.0.9.3
proxmox_ipv6: fd00:9::3
proxmox_ipv4_gw: 10.0.9.254
proxmox_ipv6_gw: fd00:9::fffe
proxmox_dns:
  - 10.0.9.254
  - fd00:9::fffe

optane_disk: /dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_BTOC14120WNT118B
nvme_disk: /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNZFNB11046K

zfs_pool: rpool
zfs_root_partition_size_gb: 32
EOF

cat > host_vars/pve04.yml <<'EOF'
proxmox_nic: enp4s0

proxmox_ipv4: 10.0.9.4
proxmox_ipv6: fd00:9::4
proxmox_ipv4_gw: 10.0.9.254
proxmox_ipv6_gw: fd00:9::fffe
proxmox_dns:
  - 10.0.9.254
  - fd00:9::fffe

nvme_disk: "/dev/sda"

zfs_pool: rpool
zfs_root_partition_size_gb: 64
EOF

# === Group Vars ===
cat > group_vars/infraweb.yml <<'EOF'
http_file_root: '/srv/webroot/pxe'
http_web_root: 'http://infraweb.sulibot.com'
hostname_domain: 'sulibot.com'
zfsbootmenu_url: 'https://github.com/zbm-dev/zfsbootmenu/releases/download/v3.0.1/zfsbootmenu-release-x86_64-v3.0.1-linux6.12.EFI'
zfsbootmenu_file: '{{ http_file_root }}/zfsbootmenu.efi'
EOF

cat > group_vars/pxe_servers.yml <<'EOF'
ipxe_file: '{{ playbook_dir }}/files/ipxe.efi'
tftp_root: '/usb1/proxmox'
EOF

cat > group_vars/tftp_servers.yml <<'EOF'
tftp_root: '/srv/tftp'
ipxe_file: '{{ playbook_dir }}/files/ipxe.efi'
EOF

cat > group_vars/pve.yml <<'EOF'
ssh_pubkey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILS7qW4IWbXx+9hk1A59X8vTtj5gCiEglr+cKNA+gRe5 sulibot@gmail.com'
proxmox_nic: 'eth0'
zfs_pool: 'rpool'
zfs_ashift: 12
zfs_options: 'ashift=12 compression=lz4 atime=off'
zfs_root_partition_size_gb: 64
root_passwd_hash: '$6$XzTLR7ZbQeayKSZk$V3C0YkflG9ZoeINgYQSt28JmKdtw3tA2.VkMHm1a.qUSh4TUt0xyTaeZ4mUSUb5qxlND1jvqOjHkQlHkMGeqd/'
pve_apt_repo: 'deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription'
pve_apt_key:  'https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg'
pkgsel_include:
  - proxmox-ve
  - postfix
  - ceph-common
  - zfs-initramfs
  - zfsutils-linux
EOF

# === Template: menu.ipxe.j2 ===
cat > templates/menu.ipxe.j2 <<'EOF'
#!ipxe

set zbm_url {{ http_web_root }}/zfsbootmenu.efi

menu --name zfsbootmenu --title "ZFSBootMenu PXE Boot Menu"
item --gap -- Proxmox Nodes
{% for node in groups['pve'] %}
item --key {{ loop.index }} {{ node }} Boot {{ node }}
{% endfor %}
item --gap --
item --key s shell iPXE Shell

choose --default shell --timeout 5000 target && goto ${target}

{% for node in groups['pve'] %}
:{{ node }}
echo Booting {{ node }} via ZFSBootMenu...
chain ${zbm_url} || goto shell
{% endfor %}

:shell
shell
EOF


cat > templates/install-proxmox.sh.j2 <<'EOF'
#!/bin/bash
set -euxo pipefail

DISK1="{{ hostvars[inventory_hostname].optane_disk }}"
DISK2="{{ hostvars[inventory_hostname].nvme_disk | default('') }}"
SIZE_GB="{{ zfs_root_partition_size_gb }}"
ZBM_EFI="/boot/efi/EFI/ZBM/ZFSBootMenu.EFI"

{% if inventory_hostname in ['pve01', 'pve02', 'pve03'] %}
# Partition both disks for mirrored ZFS root
parted -s $DISK1 mklabel gpt mkpart ESP fat32 1MiB 512MiB set 1 boot on
parted -s $DISK1 mkpart primary 512MiB ${SIZE_GB}GiB

parted -s $DISK2 mklabel gpt mkpart ESP fat32 1MiB 512MiB set 1 boot on
parted -s $DISK2 mkpart primary 512MiB ${SIZE_GB}GiB

# Create ZFS mirror
zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -O mountpoint=/ -R /mnt {{ zfs_pool }} mirror ${DISK1}2 ${DISK2}2
{% else %}
# Partition single disk for ZFS root
parted -s $DISK1 mklabel gpt mkpart ESP fat32 1MiB 512MiB set 1 boot on
parted -s $DISK1 mkpart primary 512MiB ${SIZE_GB}GiB

# Create ZFS pool
zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -O mountpoint=/ -R /mnt {{ zfs_pool }} ${DISK1}2
{% endif %}

# Create root dataset
zfs create {{ zfs_pool }}/ROOT
zfs set mountpoint=/ {{ zfs_pool }}/ROOT

# Bootstrap Debian
debootstrap bookworm /mnt http://deb.debian.org/debian
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# Chroot configuration
cat <<EOC | chroot /mnt /bin/bash
set -euxo pipefail

# Host identity
echo {{ inventory_hostname }} > /etc/hostname
echo "127.0.1.1 {{ inventory_hostname }}.{{ hostname_domain }} {{ inventory_hostname }}" >> /etc/hosts

# Locale & timezone
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "America/Los_Angeles" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# SSH access
echo 'root:{{ root_passwd_hash }}' | chpasswd -e
mkdir -p /root/.ssh
echo '{{ ssh_pubkey }}' > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Proxmox + ZFSBootMenu setup
apt update
apt install -y gnupg curl wget efibootmgr linux-image-amd64

# Add Proxmox repo and key
curl -fsSL {{ pve_apt_key }} | gpg --dearmor -o /etc/apt/trusted.gpg.d/proxmox.gpg
echo '{{ pve_apt_repo }}' > /etc/apt/sources.list.d/pve-install.list

apt update
apt install -y {{ pkgsel_include | join(' ') }}

# ZFSBootMenu installation
mkdir -p /boot/efi/EFI/ZBM
cp {{ zfsbootmenu_file }} ${ZBM_EFI}

# EFI boot entry creation
efibootmgr --create --disk ${DISK1} --part 1 \
  --label "ZFSBootMenu" \
  --loader '\EFI\ZBM\ZFSBootMenu.EFI'

{% if inventory_hostname in ['pve01', 'pve02', 'pve03'] %}
efibootmgr --create --disk ${DISK2} --part 1 \
  --label "ZFSBootMenu Mirror" \
  --loader '\EFI\ZBM\ZFSBootMenu.EFI'
{% endif %}

# Enable SSH at boot
systemctl enable ssh
EOC

# Cleanup mounts and export ZFS pool
umount /mnt/dev || true
umount /mnt/proc || true
umount /mnt/sys || true
zpool export {{ zfs_pool }}

echo "✅ Installation complete for {{ inventory_hostname }}. Ready to boot into ZFSBootMenu."
EOF

# === Role: pxe_routeros ===
cat > roles/pxe_routeros/tasks/main.yml <<'EOF'
- name: Ensure Proxmox directory exists on RouterOS
  community.routeros.command:
    commands:
      - ':if ([:len [/file find name="usb1/proxmox"]] = 0) do={ /file add name=usb1/proxmox type=directory }'

- name: Check if iPXE binary is present locally
  stat:
    path: '{{ ipxe_file }}'
  register: ipxe_stat

- name: Fetch iPXE binary via scp if missing
  ansible.builtin.shell: >
    scp -i ~/.ssh/id_ed25519 root@10.0.9.95:/root/ipxe/src/bin-x86_64-efi/ipxe.efi {{ ipxe_file }}
  when: not ipxe_stat.stat.exists

- name: Upload iPXE EFI binary
  ansible.netcommon.net_put:
    src: '{{ ipxe_file }}'
    dest: '{{ tftp_root }}/ipxe.efi'
    mode: '0644'

- name: Add TFTP entry for iPXE
  community.routeros.command:
    commands:
      - '/ip tftp add real-filename="{{ tftp_root }}/ipxe.efi" req-filename=ipxe.efi'

- name: Enable TFTP server on RouterOS
  community.routeros.command:
    commands:
      - '/ip tftp set enabled=yes address=0.0.0.0 port=69'
EOF

# === Role: tftp ===
cat > roles/tftp/tasks/main.yml <<'EOF'
- name: Ensure TFTP root exists
  file:
    path: '{{ tftp_root }}'
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Deploy iPXE EFI binary to TFTP root
  copy:
    src: '{{ ipxe_file }}'
    dest: '{{ tftp_root }}/ipxe.efi'
    owner: root
    group: root
    mode: '0644'

- name: Restart TFTP service
  service:
    name: tftpd-hpa
    state: restarted
EOF

# === Role: zfsbootmenu_http ===
cat > roles/zfsbootmenu_http/tasks/main.yml <<'EOF'
- name: Ensure HTTP root path exists
  file:
    path: '{{ http_file_root }}/install'
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Ensure ZFSBootMenu image exists
  stat:
    path: '{{ zfsbootmenu_file }}'
  register: zbm_stat

- name: Download ZFSBootMenu EFI if missing
  get_url:
    url: '{{ zfsbootmenu_url }}'
    dest: '{{ zfsbootmenu_file }}'
    mode: '0644'
  when: not zbm_stat.stat.exists

- name: Deploy install script per node
  template:
    src: install-proxmox.sh.j2
    dest: '{{ http_file_root }}/install/{{ item }}-install.sh'
    mode: '0755'
  loop: '{{ groups["pve"] }}'
  vars:
    inventory_hostname: '{{ item }}'
EOF

# === Playbook ===
cat > provision-pxe.yml <<'EOF'
---
- name: Prepare RouterOS for TFTP + iPXE
  hosts: pxe_servers
  gather_facts: false
  vars_files:
    - group_vars/pxe_servers.yml
    - group_vars/infraweb.yml
  roles:
    - pxe_routeros

- name: Configure TFTP server(s)
  hosts: tftp_servers
  gather_facts: false
  vars_files:
    - group_vars/tftp_servers.yml
  roles:
    - tftp

- name: Configure HTTP server for ZFSBootMenu provisioning
  hosts: infraweb
  gather_facts: false
  vars_files:
    - group_vars/infraweb.yml
    - group_vars/pve.yml
  roles:
    - zfsbootmenu_http
EOF
