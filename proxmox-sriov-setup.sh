#!/bin/bash
set -euo pipefail

# SR-IOV Setup for Intel UHD Graphics 770 on Proxmox
# Run this on each Proxmox host: pve01, pve02, pve03
# For Raptor Lake (14th gen) and Alder Lake (12th gen) CPUs

echo "==================================================="
echo "Intel iGPU SR-IOV Setup for Proxmox"
echo "==================================================="
echo ""

# Detect kernel version
KERNEL_VERSION=$(uname -r)
echo "Current kernel: $KERNEL_VERSION"

# Check if running on Proxmox
if [ ! -f /etc/pve/.version ]; then
    echo "ERROR: This doesn't appear to be a Proxmox host"
    exit 1
fi

PVE_VERSION=$(cat /etc/pve/.version)
echo "Proxmox VE version: $PVE_VERSION"
echo ""

# Step 1: Install dependencies
echo "Step 1: Installing build dependencies..."
apt update
apt install -y \
    git \
    dkms \
    build-essential \
    pve-headers-${KERNEL_VERSION} \
    mokutil

# Step 2: Check if Secure Boot is enabled
echo ""
echo "Step 2: Checking Secure Boot status..."
if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    echo "WARNING: Secure Boot is ENABLED"
    echo "You need to either:"
    echo "  1. Disable Secure Boot in BIOS, OR"
    echo "  2. Sign the i915-sriov-dkms module with your MOK key"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "Secure Boot is disabled - good!"
fi

# Step 3: Clone and install i915-sriov-dkms
echo ""
echo "Step 3: Installing i915-sriov-dkms driver..."

# Remove any existing installation
if [ -d /usr/src/i915-sriov-dkms ]; then
    echo "Removing existing i915-sriov-dkms..."
    dkms remove i915-sriov-dkms/$(cat /usr/src/i915-sriov-dkms/VERSION 2>/dev/null || echo "unknown") --all 2>/dev/null || true
    rm -rf /usr/src/i915-sriov-dkms
fi

# Clone repository
cd /usr/src
git clone https://github.com/strongtz/i915-sriov-dkms.git
cd i915-sriov-dkms

# Get version
DRIVER_VERSION=$(cat VERSION)
echo "Driver version: $DRIVER_VERSION"

# Install via DKMS
dkms add .
dkms install i915-sriov-dkms/${DRIVER_VERSION} -k ${KERNEL_VERSION}

echo "i915-sriov-dkms installed successfully!"

# Step 4: Configure kernel parameters
echo ""
echo "Step 4: Configuring kernel boot parameters..."

# Backup grub config
cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d-%H%M%S)

# Remove any existing Intel iGPU parameters and add new ones
sed -i 's/intel_iommu=[^ ]*//g' /etc/default/grub
sed -i 's/i915\.[^ ]*//g' /etc/default/grub
sed -i 's/iommu=[^ ]*//g' /etc/default/grub

# Add SR-IOV parameters
if ! grep -q "intel_iommu=on" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 /' /etc/default/grub
fi

echo "Kernel parameters added:"
echo "  - intel_iommu=on       : Enable IOMMU for VT-d"
echo "  - iommu=pt             : Passthrough mode"
echo "  - i915.enable_guc=3    : Enable GuC and HuC firmware"
echo "  - i915.max_vfs=7       : Maximum 7 virtual functions"

# Update grub
update-grub

# Step 5: Blacklist default i915 driver (optional, for clarity)
echo ""
echo "Step 5: Module configuration..."
cat > /etc/modprobe.d/i915-sriov.conf <<EOF
# SR-IOV configuration for Intel i915
options i915 enable_guc=3 max_vfs=7
EOF

echo "Module options configured"

# Step 6: Create systemd service to enable VFs at boot
echo ""
echo "Step 6: Creating systemd service for VF enablement..."

cat > /etc/systemd/system/intel-sriov-enable.service <<'EOF'
[Unit]
Description=Enable Intel iGPU SR-IOV Virtual Functions
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'echo 7 > /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs || echo 7 > /sys/class/drm/card0/device/sriov_numvfs'
ExecStop=/bin/bash -c 'echo 0 > /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs || echo 0 > /sys/class/drm/card0/device/sriov_numvfs'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable intel-sriov-enable.service

echo "Systemd service created and enabled"

# Summary
echo ""
echo "==================================================="
echo "SR-IOV Setup Complete!"
echo "==================================================="
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. REBOOT this Proxmox host:"
echo "   reboot"
echo ""
echo "2. After reboot, verify SR-IOV is working:"
echo "   lspci | grep VGA"
echo "   cat /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs"
echo "   ls -la /sys/bus/pci/devices/0000:00:02.*/sriov"
echo ""
echo "3. You should see 7 VGA controllers (1 PF + 7 VFs)"
echo ""
echo "4. To pass a VF to a VM, add to VM config:"
echo "   qm set <VMID> --hostpci0 0000:00:02.1,pcie=1"
echo ""
echo "==================================================="
