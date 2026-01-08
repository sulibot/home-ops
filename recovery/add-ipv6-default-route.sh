#!/bin/bash
# Emergency recovery script to add IPv6 default route on PVE nodes
# Run this script locally on each PVE node via console/IPMI if SSH is not working
#
# This adds a temporary IPv6 default route via RouterOS on vlan10
# The route will be automatically replaced when OSPF/BGP comes back up

# RouterOS link-local address on vlan10
ROUTER_LL="fe80::10"
INTERFACE="vmbr0.10"

# Check if we already have a default IPv6 route
if ip -6 route show default | grep -q "default"; then
    echo "Default IPv6 route already exists:"
    ip -6 route show default
    echo ""
    echo "If you want to add the backup route anyway, delete the existing one first:"
    echo "  ip -6 route del default"
else
    echo "No default IPv6 route found. Adding backup route via RouterOS..."
    ip -6 route add default via $ROUTER_LL dev $INTERFACE metric 100
    echo "Done! Route added:"
    ip -6 route show default
fi

echo ""
echo "Testing connectivity to workstation network (fd00:30::/64)..."
if ping6 -c 2 fd00:30::fffe > /dev/null 2>&1; then
    echo "✓ Successfully reached fd00:30::fffe (RouterOS lo)"
else
    echo "✗ Cannot reach fd00:30::fffe - check RouterOS routing"
fi
