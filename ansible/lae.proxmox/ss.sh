#!/bin/bash
set -euo pipefail

ROLES_DIR="roles"
DISK_WIPE_DIR="$ROLES_DIR/disk_wipe/tasks"
DISK_LAYOUT_DIR="$ROLES_DIR/disk_layout/tasks"

mkdir -p "$DISK_WIPE_DIR" "$DISK_LAYOUT_DIR"

echo "[+] Creating disk_wipe role..."

cat > "$DISK_WIPE_DIR/main.yml" <<'EOF'
---
# Remove LVM metadata, partitions >3 on optane_disk, and update kernel

- name: Get VG name from optane partition 4 (if any)
  shell: |
    pvs --noheadings -o vg_name {{ optane_disk }}4 2>/dev/null | awk '{$1=$1};1'
  register: detected_vg
  changed_when: false
  failed_when: false

- name: Get list of LVs in detected VG
  shell: |
    lvs --noheadings -o lv_name {{ detected_vg.stdout }} 2>/dev/null | awk '{$1=$1};1'
  register: lv_list
  when: detected_vg.stdout != ""
  changed_when: false
  failed_when: false

- name: Remove LVs from detected VG
  command: lvremove -fy /dev/{{ detected_vg.stdout }}/{{ item }}
  loop: "{{ lv_list.stdout_lines }}"
  when:
    - detected_vg.stdout != ""
    - lv_list.stdout_lines is defined
  ignore_errors: true

- name: Remove detected VG
  command: vgremove -fy {{ detected_vg.stdout }}
  when: detected_vg.stdout != ""
  ignore_errors: true

- name: Remove PV from optane partition 4
  command: pvremove -ffy {{ optane_disk }}4
  ignore_errors: true

- name: Delete partitions > 3 from optane_disk
  command: sgdisk --delete={{ item }} {{ optane_disk }}
  loop: "{{ range(4, 16) | list }}"

- name: Wipe all partitions on nvme_disk and sata_disks
  shell: |
    for dev in {{ nvme_disk }} {{ sata_disks | join(' ') }}; do
      wipefs -a "$dev" || true
      sgdisk --zap-all "$dev" || true
    done

- name: Inform kernel of new partition table
  command: partprobe {{ optane_disk }}

- name: Wait for udev to settle
  command: udevadm settle
EOF

echo "[+] Creating disk_layout role..."

cat > "$DISK_LAYOUT_DIR/main.yml" <<'EOF'
---
# Add new Ceph partition and LVM layout to optane_disk and sata_disks

- name: Create partition 4 on optane_disk
  command: >
    sgdisk --new=4:{{ optane_db_start }}:0 --typecode=4:8e00 {{ optane_disk }}

- name: Wait for /dev/disk/by-id path to appear for partition 4
  wait_for:
    path: "{{ optane_disk }}4"
    timeout: 10

- name: Create LVM PV on optane partition 4
  command: pvcreate -ffy {{ optane_disk }}4

- name: Create VG on optane partition 4
  command: vgcreate {{ ceph_db_vg }} {{ optane_disk }}4

- name: Create DB LVs for each OSD ID
  loop: "{{ ceph_osd_ids }}"
  loop_control:
    label: "osd{{ item }}-db"
  command: lvcreate -L {{ ceph_db_lv_size }} -n osd{{ item }}-db {{ ceph_db_vg }}

- name: Partition SATA disks into 2 equal partitions each
  shell: |
    for dev in {{ sata_disks | join(' ') }}; do
      size=$(blockdev --getsz "$dev")
      half=$((size / 2))
      sgdisk --zap-all "$dev"
      sgdisk --new=1:2048:$((2048 + half - 1)) --typecode=1:8300 "$dev"
      sgdisk --new=2:$((2048 + half)):0 --typecode=2:8300 "$dev"
    done
EOF

echo "[✓] Roles created at $ROLES_DIR/"

