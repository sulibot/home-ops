#!/bin/bash
# Emergency script to manually add IPv6 default route on PVE nodes
# Run this locally on each PVE node (pve01, pve02, pve03) via console/IPMI
#
# Usage: bash add-default-route-manual.sh

echo "Adding IPv6 default route via RouterOS custom link-local..."
ip -6 route add default via fe80::10:fffe dev vmbr0.10 metric 1024 2>&1 || echo "Route may already exist"

echo ""
echo "Current IPv6 default routes:"
ip -6 route show default

echo ""
echo "Testing connectivity to workstation network (fd00:30::fffe)..."
if ping6 -c 2 fd00:30::fffe > /dev/null 2>&1; then
    echo "✓ SUCCESS: Can reach fd00:30::fffe (RouterOS lo)"
else
    echo "✗ FAILED: Cannot reach fd00:30::fffe - check RouterOS"
fi

echo ""
echo "Testing connectivity to internet (2001:4860:4860::8888)..."
if ping6 -c 2 2001:4860:4860::8888 > /dev/null 2>&1; then
    echo "✓ SUCCESS: Can reach Google DNS via IPv6"
else
    echo "✗ FAILED: No IPv6 internet connectivity"
fi
