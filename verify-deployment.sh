#!/bin/bash
# Proxmox Network and BGP Deployment Verification Script
# Run this on each Proxmox node via console access

echo "=========================================="
echo "Proxmox Node Deployment Verification"
echo "=========================================="
echo ""

# Get hostname
echo "Node: $(hostname)"
echo ""

# Check network interfaces status
echo "--- Network Interfaces Status ---"
echo "lo-infra interface:"
ip addr show lo-infra 2>/dev/null || echo "ERROR: lo-infra interface not found"
echo ""

echo "lo-svcs interface:"
ip addr show lo-svcs 2>/dev/null || echo "ERROR: lo-svcs interface not found"
echo ""

# Check IPv6 forwarding on lo-infra
echo "--- IPv6 Forwarding Status ---"
echo -n "lo-infra forwarding: "
cat /proc/sys/net/ipv6/conf/lo-infra/forwarding 2>/dev/null || echo "ERROR: Cannot read forwarding status"

echo -n "Global IPv6 forwarding: "
cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo "ERROR: Cannot read forwarding status"
echo ""

# Check FRR service status
echo "--- FRR Service Status ---"
systemctl status frr --no-pager | grep -E "(Active|Loaded)" || echo "ERROR: FRR service status unavailable"
echo ""

# Check OSPF neighbors
echo "--- OSPF Neighbors (IPv4) ---"
vtysh -c "show ip ospf neighbor" 2>/dev/null || echo "ERROR: Cannot query OSPF neighbors"
echo ""

echo "--- OSPFv3 Neighbors (IPv6) ---"
vtysh -c "show ipv6 ospf6 neighbor" 2>/dev/null || echo "ERROR: Cannot query OSPFv3 neighbors"
echo ""

# Check OSPF routes for loopback addresses
echo "--- OSPF Routes to BGP Loopbacks ---"
echo "IPv4 routes to 10.255.0.0/24:"
ip route show | grep "10.255.0" || echo "No routes found"
echo ""

echo "IPv6 routes to fd00:0:0:ffff::/64:"
ip -6 route show | grep "fd00:0:0:ffff" || echo "No routes found"
echo ""

# Check BGP session status
echo "--- BGP Session Status ---"
echo "IPv6 BGP Summary:"
vtysh -c "show bgp ipv6 summary" 2>/dev/null || echo "ERROR: Cannot query BGP status"
echo ""

# Test connectivity to other BGP loopbacks
echo "--- Connectivity Tests ---"
NODE_ID=$(hostname | grep -oE '[0-9]+$')
for i in 1 2 3; do
    if [ "$i" != "$NODE_ID" ]; then
        echo -n "Ping to pve0$i (fd00:0:0:ffff::$i): "
        ping6 -c 2 -W 2 fd00:0:0:ffff::$i >/dev/null 2>&1 && echo "OK" || echo "FAILED"
    fi
done
echo ""

# Check Proxmox cluster status
echo "--- Proxmox Cluster Status ---"
pvecm status || echo "ERROR: Cannot query cluster status"
echo ""

# Check if FRR needs restart
echo "--- FRR Configuration Status ---"
echo "Last FRR config modification:"
ls -lh /etc/frr/frr.conf | awk '{print $6, $7, $8}'
echo ""

# Suggest next steps
echo "=========================================="
echo "Quick Fix Commands (if needed):"
echo "=========================================="
echo "# Restart FRR to apply configuration:"
echo "systemctl restart frr"
echo ""
echo "# Manually enable IPv6 forwarding on lo-infra:"
echo "echo 1 > /proc/sys/net/ipv6/conf/lo-infra/forwarding"
echo ""
echo "# Reload network interfaces:"
echo "ifreload -a"
echo ""
echo "# Check FRR logs for errors:"
echo "journalctl -u frr -n 50 --no-pager"
echo ""
