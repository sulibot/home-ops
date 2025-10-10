#!/usr/bin/env bash
# Dracut Remote Installer Builder (for PVE kernel with ZFS built-in)
# – Uses default dracut modules
# – Registers an initqueue online hook to fetch and run installer

set -euo pipefail
IFS=$'\n\t'
export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------
# PREPARE BUILD ENVIRONMENT
# --------------------------------------------------
apt-get update
apt-get install -y --no-install-recommends \
  dracut-network \
  zfsutils-linux \
  gdisk \
  debootstrap \
  dosfstools \
  wget \
  curl \
  iproute2 \
  open-iscsi \
  kmod \
  util-linux \
  coreutils \
  findutils

# --------------------------------------------------
# Determine Target Kernel Version
# --------------------------------------------------
KVER=$(ls /lib/modules | grep pve | sort -V | tail -n1)
echo "[info] Building initramfs for kernel: $KVER"

# --------------------------------------------------
# Create Custom Dracut Module (90remote-build)
# --------------------------------------------------
MODULE_DIR="/usr/lib/dracut/modules.d/90remote-build"
mkdir -p "$MODULE_DIR"
chmod -R a+rx "$MODULE_DIR"

# Add a static resolv.conf into module
cat > "$MODULE_DIR/resolv.conf" <<EOF
nameserver 10.0.9.254
EOF

# module-setup.sh
cat > "$MODULE_DIR/module-setup.sh" <<EOF
#!/usr/bin/env bash

depends() {
    echo network
}

install() {
    # Core dracut tools
    inst_multiple \
      /bin/bash \
      /usr/bin/curl \
      /usr/bin/wget \
      /usr/sbin/ip \
      /sbin/dhclient \
      /usr/sbin/zpool \
      /usr/sbin/zfs \
      /usr/sbin/dhclient-script

    # Installer support binaries (with deps)
    inst_binary wipefs \
               sgdisk \
               debootstrap \
               mkfs.vfat \
               find

    # Filesystem helpers
    inst_multiple \
      /bin/mount \
      /bin/umount \
      /bin/cat

    # Static DNS inside initramfs
    inst_simple "$moddir/resolv.conf" "etc/resolv.conf"

    # Include ZFS modules and install hook
    instmods zfs zcommon
    inst_hook initqueue/online 50 "$moddir/init.sh"
}

installkernel() {
    return 0
}
EOF
chmod +x "$MODULE_DIR/module-setup.sh"

# init.sh: executed when network is online
cat > "$MODULE_DIR/init.sh" <<'EOF'
#!/usr/bin/env bash
# Debug-enabled init script
set +u -x
exec >/dev/console 2>&1

echo "[remote-build] initqueue online hook started"

echo "[remote-build] /proc/cmdline: $(cat /proc/cmdline)"

# Bring up first non-loopback interface
iface=""
for IF in $(ls /sys/class/net | grep -Ev '^lo$'); do
  ip link set dev "$IF" up &>/dev/null && iface="$IF" && break
done

echo "[remote-build] selected iface: ${iface:-<none>}"
[[ -z "$iface" ]] && exec sh

# Obtain DHCP (including DNS via dhclient-script)
DHCLIENT_IFACE="$iface" dhclient -sf /usr/sbin/dhclient-script -v || echo "[remote-build] DHCP failed"

echo "[remote-build] IP addresses: $(ip addr show dev $iface)"

echo "[remote-build] Contents of /etc/resolv.conf:"
cat /etc/resolv.conf || echo "[remote-build] /etc/resolv.conf missing"

# Extract installer URL
script=""
for arg in $(cat /proc/cmdline); do
  case "$arg" in
    script=*) script="${arg#script=}"; break;;
  esac
done

echo "[remote-build] installer URL: ${script:-<none>}"
if [[ -n "$script" ]]; then
  mkdir -p /tmp
  curl -fsSL "$script" -o /tmp/install.sh && chmod +x /tmp/install.sh && exec /tmp/install.sh
fi

# Fallback shell
exec sh
EOF
chmod +x "$MODULE_DIR/init.sh"

# Dracut config overrides
cat > /etc/dracut.conf.d/remote-build.conf <<EOF
add_dracutmodules+=" remote-build "
force_drivers+=" zfs "
EOF

# Build initramfs
echo "[build] Generating initramfs for kernel $KVER..."
dracut --force --verbose --kver "$KVER" /boot/initrd.img-pve

# Validate
if [[ -f /boot/initrd.img-pve ]]; then
  echo "[✓] initramfs created: /boot/initrd.img-pve"
else
  echo "[✗] build failed"
  exit 1
fi

lsinitramfs /boot/initrd.img-pve | grep 'initqueue/online/50-init.sh' || echo HOOK_MISSING
lsinitramfs /boot/initrd.img-pve | grep 'usr/sbin/zfs' || echo ZFS_MISSING
