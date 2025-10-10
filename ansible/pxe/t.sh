#!/bin/bash
set -euo pipefail

BASE_DIR="roles/build_pxe_root"
mkdir -p "$BASE_DIR/tasks" "$BASE_DIR/defaults" playbooks

echo "Writing playbook to playbooks/build-pxe-root.yml..."
cat > playbooks/build-pxe-root.yml <<'EOF'
- name: Build PXE root filesystem for Proxmox install
  hosts: pxe_builder
  become: true
  roles:
    - build_pxe_root
EOF

echo "Writing defaults to $BASE_DIR/defaults/main.yml..."
cat > "$BASE_DIR/defaults/main.yml" <<'EOF'
pxe_root_dir: "/var/lib/pxe-rootfs/proxmox"
debian_codename: "bookworm"
debian_mirror: "http://deb.debian.org/debian"
pxe_output_initrd: "{{ pxe_root_dir }}/initrd-proxmox.gz"
pxe_chroot: "{{ pxe_root_dir }}/chroot"

pxe_debootstrap_packages:
  - bash
  - coreutils
  - util-linux
  - busybox
  - gzip
  - xz-utils
  - wget
  - curl
  - gnupg
  - gpgv
  - jq
  - iproute2
  - net-tools
  - ethtool
  - isc-dhcp-client

pxe_chroot_packages:
  - systemd
  - systemd-sysv
  - dbus
  - gdisk
  - parted
  - dosfstools
  - wipefs
  - e2fsprogs
  - btrfs-progs
  - zfsutils-linux
  - zfs-dkms
  - linux-headers-amd64
  - grub-efi-amd64
  - grub-efi-amd64-bin
  - grub-common
  - os-prober
  - initramfs-tools
  - initramfs-tools-core
  - locales
  - tzdata
  - chrony
  - systemd-resolved
  - hostname
  - nano
  - vim
  - htop
  - dstat
  - rsync
  - pv
  - progress
  - openssh-server
EOF

echo "Writing tasks to $BASE_DIR/tasks/main.yml..."
cat > "$B

