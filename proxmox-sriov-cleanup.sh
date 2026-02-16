#!/bin/bash
set -euo pipefail

# Cleanup existing i915-sriov-dkms installation on Proxmox
# Run this FIRST if you have an existing installation

echo "==================================================="
echo "Cleaning up existing i915-sriov-dkms installation"
echo "==================================================="
echo ""

# Step 1: Disable VFs
echo "Step 1: Disabling any active virtual functions..."
if [ -f /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs ]; then
    echo 0 > /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs 2>/dev/null || true
fi
if [ -f /sys/class/drm/card0/device/sriov_numvfs ]; then
    echo 0 > /sys/class/drm/card0/device/sriov_numvfs 2>/dev/null || true
fi
echo "VFs disabled"

# Step 2: Stop and disable systemd service
echo ""
echo "Step 2: Removing systemd service..."
if systemctl is-enabled intel-sriov-enable.service 2>/dev/null; then
    systemctl stop intel-sriov-enable.service
    systemctl disable intel-sriov-enable.service
fi
rm -f /etc/systemd/system/intel-sriov-enable.service
systemctl daemon-reload
echo "Systemd service removed"

# Step 3: Remove DKMS modules
echo ""
echo "Step 3: Removing DKMS modules..."

# Find all i915-sriov-dkms versions
DKMS_VERSIONS=$(dkms status | grep i915-sriov-dkms | awk '{print $2}' | tr -d ',' || echo "")

if [ -n "$DKMS_VERSIONS" ]; then
    for VERSION in $DKMS_VERSIONS; do
        echo "Removing i915-sriov-dkms/$VERSION..."
        dkms remove i915-sriov-dkms/$VERSION --all || true
    done
else
    echo "No DKMS modules found"
fi

# Step 4: Remove source directory
echo ""
echo "Step 4: Removing source files..."
rm -rf /usr/src/i915-sriov-dkms*
echo "Source files removed"

# Step 5: Remove module configuration
echo ""
echo "Step 5: Removing module configuration..."
rm -f /etc/modprobe.d/i915-sriov.conf
echo "Module config removed"

# Step 6: Restore grub config (optional)
echo ""
echo "Step 6: Cleaning kernel parameters..."
echo "NOTE: You may want to manually edit /etc/default/grub to remove:"
echo "  - intel_iommu=on"
echo "  - iommu=pt"
echo "  - i915.enable_guc=3"
echo "  - i915.max_vfs=7"
echo ""
read -p "Remove SR-IOV kernel parameters from GRUB? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp /etc/default/grub /etc/default/grub.backup.cleanup.$(date +%Y%m%d-%H%M%S)
    sed -i 's/intel_iommu=on//g' /etc/default/grub
    sed -i 's/iommu=pt//g' /etc/default/grub
    sed -i 's/i915\.enable_guc=[0-9]//g' /etc/default/grub
    sed -i 's/i915\.max_vfs=[0-9]//g' /etc/default/grub
    # Clean up any double spaces
    sed -i 's/  */ /g' /etc/default/grub
    update-grub
    echo "Kernel parameters removed"
else
    echo "Skipping kernel parameter removal"
fi

# Step 7: Unload i915 module
echo ""
echo "Step 7: Unloading i915 module..."
echo "WARNING: This may cause display issues if you're using the iGPU for console"
read -p "Unload i915 module? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    modprobe -r i915 2>/dev/null || echo "Could not unload i915 (may be in use)"
fi

echo ""
echo "==================================================="
echo "Cleanup Complete!"
echo "==================================================="
echo ""
echo "To fully clean the system:"
echo "1. Reboot the Proxmox host"
echo "2. Verify the default i915 driver is loaded:"
echo "   lsmod | grep i915"
echo "   dmesg | grep i915"
echo ""
echo "Then you can run the setup script to reinstall SR-IOV"
echo "==================================================="
