#!/bin/bash
# IPv6 filter script for Proxmox - remove ULAs in fd00::XXXX:XXXX:XXXX:XXXX format after a delay

# Log to confirm the script runs
echo "IPv6 filter script triggered for $IFACE" | systemd-cat -t ipv6-filter

# Wait to ensure all addresses are assigned
#sleep 5

# Check for and remove any ULA addresses matching the fd00::XXXX:XXXX:XXXX:XXXX pattern
for ipv6_address in $(ip -6 addr show dev vmbr0 | grep -oP 'fd00::[0-9a-fA-F]{4}:[0-9a-fA-F]{4}:[0-9a-fA-F]{4}:[0-9a-fA-F]{4}/64'); do
    echo "Removing ULA address: $ipv6_address from vmbr0" | systemd-cat -t ipv6-filter
    ip -6 addr del "$ipv6_address" dev vmbr0
done
