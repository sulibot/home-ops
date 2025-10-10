#!/usr/bin/env bash
# diskless_debian_initramfs.sh
# Create a minimal, stateless Debian initramfs for QEMU, bare-metal PXE, or iPXE

set -euo pipefail
IFS=$'\n\t'

# --- Logging ---
readonly LOGFILE="/var/log/diskless_initramfs.log"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

# --- Configuration ---
readonly CHROOT_DIR="/stable-chroot"
readonly DEBIAN_MIRROR="http://deb.debian.org/debian"
readonly DEBIAN_SUITE="stable"
readonly KERNEL_PKG="linux-image-amd64"
readonly PXE_ROOT="/mnt/tftp/proxmox"

# --- Error Handler ---
error_exit() {
  echo "ERROR at line $1: $2" >&2
  exit 1
}
trap 'error_exit $LINENO "Unexpected failure"' ERR

# --- Preconditions ---
(( EUID == 0 )) || error_exit ${LINENO} "Script must be run as root"

# --- Step 0: Non-interactive APT ---
echo "[0] Configuring APT for noninteractive installs"
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

# --- Step 1: Cleanup previous chroot ---
echo "[1] Removing existing chroot directory: ${CHROOT_DIR}"
rm -rf "${CHROOT_DIR}"

# --- Step 2: Host prerequisites ---
echo "[2] Installing host prerequisites"
apt-get update
apt-get install -y --no-install-recommends \
  debootstrap cpio gzip build-essential coreutils qemu-system-x86 qemu-utils \
  xz-utils squashfs-tools dracut-core dracut-network zstd \
  net-tools iproute2 wget curl ssh nfs-common iperf3 traceroute \
  file binutils debconf-utils

# --- Step 3: Bootstrap Debian system ---
echo "[3] Bootstrapping Debian '${DEBIAN_SUITE}'"
mkdir -p "${CHROOT_DIR}"
debootstrap --variant=minbase "${DEBIAN_SUITE}" "${CHROOT_DIR}" "${DEBIAN_MIRROR}"

# --- Step 4: Configure apt inside chroot ---
echo "[4] Configuring APT sources for contrib/non-free"
cat > "${CHROOT_DIR}/etc/apt/sources.list" <<-EOF
  deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE} main contrib non-free
  deb ${DEBIAN_MIRROR} ${DEBIAN_SUITE}-updates main contrib non-free
  deb http://security.debian.org/debian-security ${DEBIAN_SUITE}-security main contrib non-free
EOF

# --- Step 5: Mount pseudo-filesystems ---
echo "[5] Mounting /proc, /sys, /dev, and /dev/pts"
for fs in proc sys dev; do
  mkdir -p "${CHROOT_DIR}/${fs}"
  mount --bind "/${fs}" "${CHROOT_DIR}/${fs}"
done
mkdir -p "${CHROOT_DIR}/dev/pts"
mount -t devpts devpts "${CHROOT_DIR}/dev/pts"

# --- Step 6: Block services & preseed iperf3 ---
echo "[6] Installing policy-rc.d and preseeding iperf3"
install -Dm755 /dev/stdin "${CHROOT_DIR}/usr/sbin/policy-rc.d" <<-'POLICY'
#!/bin/sh
# Prevent services from starting inside chroot
exit 101
POLICY
chmod +x "${CHROOT_DIR}/usr/sbin/policy-rc.d"
echo 'iperf3 iperf3/autostart boolean false' | chroot "${CHROOT_DIR}" debconf-set-selections

# --- Step 7: Install kernel, headers, ZFS, and tools in chroot ---
echo "[7] Installing kernel, headers, ZFS, and tools"
chroot "${CHROOT_DIR}" bash -eux <<-EOF
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  # Install the generic kernel and headers meta-packages to ensure proper vmlinuz placement
  apt-get install -y --no-install-recommends \
    ${KERNEL_PKG} linux-headers-amd64 dracut-core dracut-network \
    debconf-utils iproute2 net-tools iputils-ping iperf3 traceroute zstd
  # Install ZFS packages
  apt-get install -y --no-install-recommends zfs-initramfs zfsutils-linux
EOF

# --- Step 8: Build unified initramfs (unfiltered, excluding mounted FS) --- (unfiltered, excluding mounted FS) ---
echo "[8] Building unified initramfs without pruning but excluding mounted pseudo-filesystems"
pushd "${CHROOT_DIR}" > /dev/null
# Exclude dev, proc, sys mounts by restricting find to a single filesystem
find . -xdev -print0 \
  | cpio --null --create --verbose --format=newc \
  | gzip -9 > boot/initrd-root.img
popd > /dev/null

# --- Step 9: Create init symlink ---
echo "[9] Linking /init to systemd"
ln -sf usr/bin/systemd "${CHROOT_DIR}/init"

# --- Step 10: Copy artifacts ---
echo "[10] Copying artifacts to ${PXE_ROOT}"
mkdir -p "${PXE_ROOT}"
# Find the latest vmlinuz in chroot boot directory, or fallback to root-level (include symlinks)
KERNEL_FILE=$(find "${CHROOT_DIR}/boot" -maxdepth 1 -name 'vmlinuz-*' | sort | tail -n1)
if [[ -z "${KERNEL_FILE}" ]]; then
  echo "No kernel in ${CHROOT_DIR}/boot, checking root-level"
  # include symlinks at chroot root
  KERNEL_FILE=$(find "${CHROOT_DIR}" -maxdepth 1 -name 'vmlinuz*' | sort | tail -n1)
fi
[[ -n "${KERNEL_FILE}" ]] || error_exit ${LINENO} "Kernel not found anywhere in chroot"
echo "Using kernel: ${KERNEL_FILE}"
cp -av "${KERNEL_FILE}" "${PXE_ROOT}/vmlinuz"
cp -av "${CHROOT_DIR}/boot/initrd-root.img" "${PXE_ROOT}/initrd.img"

# --- Finish ---
echo "All done. Artifacts available in ${PXE_ROOT}"
cat <<-EOF
--- QEMU Example ---
qemu-system-x86_64 -enable-kvm -m 2G \
    -kernel ${PXE_ROOT}/vmlinuz \
    -initrd ${PXE_ROOT}/initrd.img
EOF
