#!/bin/bash
# Emergency script to manually add IPv4 and IPv6 default routes on PVE nodes
# Run this locally on each PVE node (pve01, pve02, pve03) via console/IPMI
#
# Usage: bash add-default-routes.sh

echo "=== Adding backup default routes via RouterOS ==="
echo ""

echo "Adding IPv4 default route via 10.10.0.254..."
ip route add default via 10.10.0.254 dev vmbr0.10 metric 1024 2>&1 || echo "  (Route may already exist)"

echo "Adding IPv6 default route via fe80::10:fffe..."
ip -6 route add default via fe80::10:fffe dev vmbr0.10 metric 1024 2>&1 || echo "  (Route may already exist)"

echo ""
echo "=== Current default routes ==="
echo "IPv4:"
ip route show default
echo ""
echo "IPv6:"
ip -6 route show default

echo ""
echo "=== Connectivity tests ==="
echo "Testing IPv4 to RouterOS (10.10.0.254)..."
if ping -c 2 -W 2 10.10.0.254 > /dev/null 2>&1; then
    echo "  ✓ SUCCESS: Can reach 10.10.0.254"
else
    echo "  ✗ FAILED: Cannot reach 10.10.0.254"
fi

echo "Testing IPv6 to RouterOS (fd00:30::fffe)..."
if ping6 -c 2 -W 2 fd00:30::fffe > /dev/null 2>&1; then
    echo "  ✓ SUCCESS: Can reach fd00:30::fffe"
else
    echo "  ✗ FAILED: Cannot reach fd00:30::fffe"
fi

echo "Testing IPv4 internet (8.8.8.8)..."
if ping -c 2 -W 2 8.8.8.8 > /dev/null 2>&1; then
    echo "  ✓ SUCCESS: IPv4 internet working"
else
    echo "  ✗ FAILED: No IPv4 internet"
fi

echo "Testing IPv6 internet (2001:4860:4860::8888)..."
if ping6 -c 2 -W 2 2001:4860:4860::8888 > /dev/null 2>&1; then
    echo "  ✓ SUCCESS: IPv6 internet working"
else
    echo "  ✗ FAILED: No IPv6 internet"
fi

echo ""
echo "=== Summary ==="
echo "Node: $(hostname)"
echo "Routes added with metric 1024 (lowest priority)"
echo "These will be overridden by OSPF/BGP when available (metric 20)"
