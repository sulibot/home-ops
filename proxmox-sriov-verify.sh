#!/bin/bash
set -euo pipefail

# Verify SR-IOV setup on Proxmox host
# Run this after setup and reboot to verify everything is working

echo "==================================================="
echo "Intel iGPU SR-IOV Verification"
echo "==================================================="
echo ""

# Get hostname
HOSTNAME=$(hostname)
echo "Host: $HOSTNAME"
echo "Kernel: $(uname -r)"
echo ""

# Check 1: VT-d enabled
echo "✓ Checking IOMMU/VT-d status..."
if dmesg | grep -q "DMAR: IOMMU enabled"; then
    echo "  ✅ IOMMU is enabled"
else
    echo "  ❌ IOMMU not detected - check BIOS VT-d setting"
fi
echo ""

# Check 2: i915 driver loaded
echo "✓ Checking i915 driver..."
if lsmod | grep -q "^i915"; then
    I915_VERSION=$(modinfo i915 | grep -E "^version:" | awk '{print $2}')
    I915_SRCVERSION=$(modinfo i915 | grep -E "^srcversion:" | awk '{print $2}')
    echo "  ✅ i915 driver loaded"
    echo "     Version: $I915_VERSION"
    echo "     Source: $I915_SRCVERSION"

    # Check if it's the SRIOV version
    if modinfo i915 | grep -q "sriov\|strongtz"; then
        echo "     Type: i915-sriov-dkms ✅"
    else
        echo "     Type: Standard i915 ⚠️  (not SR-IOV capable)"
    fi
else
    echo "  ❌ i915 driver not loaded"
fi
echo ""

# Check 3: GPU device
echo "✓ Checking GPU device..."
GPU_DEVICE=$(lspci | grep -i "vga\|display" | grep -i intel || echo "")
if [ -n "$GPU_DEVICE" ]; then
    echo "  ✅ Intel GPU found:"
    echo "     $GPU_DEVICE"
else
    echo "  ❌ No Intel GPU detected"
fi
echo ""

# Check 4: SR-IOV capability
echo "✓ Checking SR-IOV capability..."
if [ -f /sys/devices/pci0000:00/0000:00:02.0/sriov_totalvfs ]; then
    TOTAL_VFS=$(cat /sys/devices/pci0000:00/0000:00:02.0/sriov_totalvfs)
    CURRENT_VFS=$(cat /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs)
    echo "  ✅ SR-IOV capable"
    echo "     Max VFs: $TOTAL_VFS"
    echo "     Active VFs: $CURRENT_VFS"
elif [ -f /sys/class/drm/card0/device/sriov_totalvfs ]; then
    TOTAL_VFS=$(cat /sys/class/drm/card0/device/sriov_totalvfs)
    CURRENT_VFS=$(cat /sys/class/drm/card0/device/sriov_numvfs)
    echo "  ✅ SR-IOV capable"
    echo "     Max VFs: $TOTAL_VFS"
    echo "     Active VFs: $CURRENT_VFS"
else
    echo "  ❌ SR-IOV not available"
    echo "     Possible reasons:"
    echo "     - i915-sriov-dkms not installed"
    echo "     - Kernel parameters not set"
    echo "     - Reboot required"
fi
echo ""

# Check 5: Virtual Functions
echo "✓ Checking Virtual Functions..."
VF_COUNT=$(lspci | grep -c "VGA.*Intel.*Virtual" || echo "0")
if [ "$VF_COUNT" -gt 0 ]; then
    echo "  ✅ Found $VF_COUNT Virtual Function(s):"
    lspci | grep "VGA.*Intel.*Virtual" | sed 's/^/     /'
else
    echo "  ⚠️  No Virtual Functions active"
    echo "     Run: echo 7 > /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs"
fi
echo ""

# Check 6: Kernel parameters
echo "✓ Checking kernel parameters..."
CMDLINE=$(cat /proc/cmdline)
if echo "$CMDLINE" | grep -q "intel_iommu=on"; then
    echo "  ✅ intel_iommu=on"
else
    echo "  ❌ intel_iommu=on NOT set"
fi

if echo "$CMDLINE" | grep -q "i915.enable_guc"; then
    GUC_VAL=$(echo "$CMDLINE" | grep -oP 'i915.enable_guc=\K[0-9]' || echo "not set")
    echo "  ✅ i915.enable_guc=$GUC_VAL"
else
    echo "  ⚠️  i915.enable_guc not set"
fi

if echo "$CMDLINE" | grep -q "i915.max_vfs"; then
    MAX_VFS=$(echo "$CMDLINE" | grep -oP 'i915.max_vfs=\K[0-9]' || echo "not set")
    echo "  ✅ i915.max_vfs=$MAX_VFS"
else
    echo "  ⚠️  i915.max_vfs not set"
fi
echo ""

# Check 7: Systemd service
echo "✓ Checking systemd service..."
if systemctl is-enabled intel-sriov-enable.service &>/dev/null; then
    if systemctl is-active intel-sriov-enable.service &>/dev/null; then
        echo "  ✅ intel-sriov-enable.service: enabled and active"
    else
        echo "  ⚠️  intel-sriov-enable.service: enabled but not active"
    fi
else
    echo "  ❌ intel-sriov-enable.service not enabled"
fi
echo ""

# Summary
echo "==================================================="
echo "Summary"
echo "==================================================="
if [ "$VF_COUNT" -gt 0 ]; then
    echo "✅ SR-IOV is WORKING!"
    echo ""
    echo "You can now pass VFs to VMs with:"
    echo "  qm set <VMID> --hostpci0 0000:00:02.1,pcie=1"
    echo "  qm set <VMID> --hostpci0 0000:00:02.2,pcie=1"
    echo "  ... (up to 0000:00:02.7)"
else
    echo "⚠️  SR-IOV not fully configured"
    echo ""
    echo "Check the errors above and:"
    echo "1. Ensure BIOS VT-d is enabled"
    echo "2. Run the setup script"
    echo "3. Reboot the host"
    echo "4. Enable VFs: echo 7 > /sys/devices/pci0000:00/0000:00:02.0/sriov_numvfs"
fi
echo "==================================================="
