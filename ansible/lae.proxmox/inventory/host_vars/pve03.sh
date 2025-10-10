#!/bin/bash
# ========================================================
#  Cleanup & (Re-)Initialize LVM for Ceph OSDs on pve03
# ========================================================
set -euo pipefail

# 1) Repartition sda, sdb, sdc into two equal GPT slices
echo "=== STEP 1: Repartitioning /dev/sda, /dev/sdb, /dev/sdc ==="
for disk in sda sdb sdc; do
  parted -a optimal -s "/dev/${disk}" \
    mklabel gpt \
    mkpart primary 0% 50% \
    mkpart primary 50% 100%
done
parted -a optimal -s /dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_BTOC14120WNT118B  mkpart primary 34GB 100%
# Let kernel catch up
partprobe

# 2) Zap any leftover Ceph/LVM metadata on new partitions and NVMe OSD device
echo "=== STEP 2: Zapping Ceph/LVM metadata on partitions & NVMe ==="
ZAP_PARTS=(
  "/dev/sda1" "/dev/sda2"
  "/dev/sdb1" "/dev/sdb2"
  "/dev/sdc1" "/dev/sdc2"
  "/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_BTOC14120WNT118B-part4"
)

for part in "${ZAP_PARTS[@]}"; do
  echo "---- Zapping ${part} ----"
  ceph-volume lvm zap "${part}" --destroy 2>/dev/null || true
  pvremove -ff "${part}"   2>/dev/null || true
  wipefs -a "${part}"      2>/dev/null || true
done

# 1) Repartition sda, sdb, sdc into two equal GPT slices
echo "=== STEP 1: Repartitioning /dev/sda, /dev/sdb, /dev/sdc ==="
for disk in sda sdb sdc; do
  parted -a optimal -s "/dev/${disk}" \
    mklabel gpt \
    mkpart primary 0% 50% \
    mkpart primary 50% 100%
done
parted -a optimal -s /dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_BTOC14120WNT118B  mkpart primary 34GB 100%
# Let kernel catch up
partprobe

# 3) Create (if needed) the ceph-db-vg Volume Group on the Optane/NVMe device
echo "=== STEP 3: Creating ceph-db-vg on Optane/NVMe if missing ==="
OPTVOL="/dev/disk/by-id/nvme-INTEL_SSDPEK1A118GA_BTOC14120WNT118B-part4"

if ! vgdisplay ceph-db-vg &>/dev/null; then
  echo "→ Creating PV on ${OPTVOL}"
  pvcreate "${OPTVOL}"
  echo "→ Creating VG ceph-db-vg"
  vgcreate ceph-db-vg "${OPTVOL}"
else
  echo "→ ceph-db-vg already exists, skipping."
fi

# 4) Create one 11G DB LV per OSD in OSD_ID_LIST (only if missing)
echo "=== STEP 4: Creating per-OSD DB logical volumes ==="
OSD_ID_LIST=(2 15 16 17 18 19 20)   # pve03’s OSD IDs
DB_SIZE="11G"                      # pve03 can allocate 11 GiB per LV

for osd in "${OSD_ID_LIST[@]}"; do
  lv_name="osd${osd}-db"
  if ! lvdisplay "/dev/ceph-db-vg/${lv_name}" &>/dev/null; then
    echo "→ Creating LV ${lv_name} of size ${DB_SIZE}"
    lvcreate -n "${lv_name}" -L "${DB_SIZE}" ceph-db-vg
  else
    echo "→ LV ${lv_name} already exists, skipping."
  fi
done

echo "=== pve03 cleanup & LVM setup complete ==="
