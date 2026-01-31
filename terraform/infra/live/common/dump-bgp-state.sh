#!/bin/bash
# Dump BGP state for troubleshooting

echo "=== BGP Summary ==="
vtysh -c "show bgp summary"

echo -e "\n=== BGP Neighbors ==="
vtysh -c "show bgp neighbors"

echo -e "\n=== BGP Routes (IPv4) ==="
vtysh -c "show ip bgp"

echo -e "\n=== BGP Routes (IPv6) ==="
vtysh -c "show bgp ipv6"
